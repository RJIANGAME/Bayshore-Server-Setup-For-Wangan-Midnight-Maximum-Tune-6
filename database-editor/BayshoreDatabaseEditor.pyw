"""Dependency-free graphical PostgreSQL editor for a local Bayshore server."""

from __future__ import annotations

import csv
import io
import os
import queue
import re
import subprocess
import sys
import threading
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tkinter import BooleanVar, END, StringVar, Text, Tk, Toplevel, filedialog, messagebox
from tkinter import ttk
from urllib.parse import unquote, urlparse


NULL_MARKER = "__BAYSHORE_DATABASE_EDITOR_NULL_7D3A9C__"
EDITOR_VERSION = "1.7.0"
CAR_FIELDS = (
    ("name", "Car name"), ("title", "Title"),
    ("tunePower", "Power tune"), ("tuneHandling", "Handling tune"),
    ("tuningPoints", "Tuning points"), ("odometer", "Odometer"),
    ("vsStarCount", "VS stars"), ("dressupLevel", "Dress-up level"),
    ("dressupPoint", "Dress-up points"), ("aura", "Aura"),
)


def quote_ident(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def quote_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_value(value: str | None, column: Column) -> str:
    if value is None:
        if not column.nullable:
            raise ValueError(f"{column.name} cannot be NULL.")
        return "NULL"
    return f"CAST({quote_text(value)} AS {column.pg_type})"


def row_predicate(columns: list[Column], row: list[str | None]) -> str:
    keys = [(index, column) for index, column in enumerate(columns) if column.primary_key]
    if not keys:
        raise RuntimeError("This table has no primary key, so editing is disabled.")
    return " AND ".join(
        f"{quote_ident(column.name)} IS NOT DISTINCT FROM {sql_value(row[index], column)}"
        for index, column in keys
    )


def search_predicate(expression: str, search: str) -> str:
    # Literal substring search: %, _ and backslashes are not wildcards.
    return f"strpos(lower(COALESCE({expression}, '')), lower({quote_text(search)})) > 0"


def single_statement(sql: str) -> str:
    """Reject statement batches while respecting PostgreSQL strings/comments."""
    sql = sql.strip()
    i, ended, meaningful = 0, False, False
    leading = []
    while i < len(sql):
        ch = sql[i]
        if ch.isspace():
            leading.append(" ")
            i += 1
            continue
        if sql.startswith("--", i):
            end = sql.find("\n", i)
            i = len(sql) if end < 0 else end + 1
            leading.append(" ")
            continue
        if sql.startswith("/*", i):
            depth, i = 1, i + 2
            while i < len(sql) and depth:
                if sql.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif sql.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            if depth:
                raise ValueError("The SQL block comment is not closed.")
            leading.append(" ")
            continue
        if ch == ";":
            if not meaningful or ended:
                raise ValueError("Run one SQL statement at a time.")
            ended = True
            i += 1
            continue
        if ended:
            raise ValueError("Run one SQL statement at a time; statement batches are not supported.")
        meaningful = True
        if ch in "'\"":
            escape = ch == "'" and i > 0 and sql[i - 1] in "eE" and (i < 2 or not (sql[i - 2].isalnum() or sql[i - 2] == "_"))
            quote, i = ch, i + 1
            while i < len(sql):
                if escape and sql[i] == "\\":
                    i += 2
                elif sql[i] == quote:
                    if i + 1 < len(sql) and sql[i + 1] == quote:
                        i += 2
                    else:
                        i += 1
                        break
                else:
                    i += 1
            else:
                raise ValueError("The SQL quoted value is not closed.")
            leading.append(" quoted ")
            continue
        tag = re.match(r"\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$", sql[i:]) if ch == "$" and (i == 0 or not (sql[i - 1].isalnum() or sql[i - 1] in "_$")) else None
        if tag:
            delimiter = tag.group()
            end = sql.find(delimiter, i + len(delimiter))
            if end < 0:
                raise ValueError("The SQL dollar-quoted value is not closed.")
            i = end + len(delimiter)
            leading.append(" quoted ")
            continue
        leading.append(ch)
        i += 1
    if not meaningful:
        raise ValueError("Enter a SQL statement.")
    keyword = re.match(r"\s*([A-Za-z]+)", "".join(leading))
    if keyword and keyword.group(1).upper() in {"BEGIN", "START", "COMMIT", "END", "ROLLBACK", "ABORT", "SAVEPOINT", "RELEASE", "PREPARE"}:
        raise ValueError("The editor manages transactions. Enter a query or write statement instead.")
    return sql


@dataclass
class Column:
    name: str
    pg_type: str
    nullable: bool
    default: str | None
    primary_key: bool


class BayshoreDatabase:
    def __init__(self, server_root: Path):
        self.server_root = server_root
        self.settings = self._read_settings(server_root / ".env")
        self.psql = self._find_tool("psql.exe")
        self.pg_dump = self._find_tool("pg_dump.exe")
        self.column_cache: dict[str, list[Column]] = {}

    @staticmethod
    def _read_settings(env_path: Path) -> dict[str, object]:
        if not env_path.is_file():
            raise RuntimeError(f"Bayshore configuration was not found: {env_path}")
        match = re.search(r"(?m)^POSTGRES_URL=(.+?)\s*$", env_path.read_text(encoding="utf-8"))
        if not match:
            raise RuntimeError("POSTGRES_URL is missing from .env")
        parsed = urlparse(match.group(1).strip().strip('"\''))
        if parsed.scheme not in {"postgres", "postgresql"} or not parsed.hostname or not parsed.path:
            raise RuntimeError("POSTGRES_URL in .env is invalid")
        return {
            "host": parsed.hostname,
            "port": parsed.port or 5432,
            "user": unquote(parsed.username or ""),
            "password": unquote(parsed.password or ""),
            "database": unquote(parsed.path.lstrip("/")),
        }

    def _find_tool(self, name: str) -> Path:
        candidates = [
            self.server_root / ".runtime" / "pgsql" / "bin" / name,
            self.server_root / ".runtime" / "postgresql" / "bin" / name,
        ]
        for candidate in candidates:
            if candidate.is_file():
                return candidate
        raise RuntimeError(f"Bundled PostgreSQL tool was not found: {name}")

    def _environment(self) -> dict[str, str]:
        env = os.environ.copy()
        env["PGPASSWORD"] = str(self.settings["password"])
        env["PGCLIENTENCODING"] = "UTF8"
        env["PGCONNECT_TIMEOUT"] = "5"
        env["PGOPTIONS"] = "-c standard_conforming_strings=on"
        return env

    def _base_args(self) -> list[str]:
        return [
            str(self.psql), "-X", "-q", "-v", "ON_ERROR_STOP=1",
            "-h", str(self.settings["host"]), "-p", str(self.settings["port"]),
            "-U", str(self.settings["user"]), "-d", str(self.settings["database"]),
        ]

    def run(self, sql: str, *, csv_output: bool = False) -> str:
        args = self._base_args()
        if csv_output:
            args.extend(["--csv", "-P", f"null={NULL_MARKER}"])
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        result = subprocess.run(
            args,
            input=sql,
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            env=self._environment(),
            timeout=90,
            creationflags=flags,
        )
        if result.returncode:
            detail = (result.stderr or result.stdout).strip()
            raise RuntimeError(detail or f"psql failed with exit code {result.returncode}")
        return result.stdout

    def query(self, sql: str) -> tuple[list[str], list[list[str | None]]]:
        output = self.run(sql, csv_output=True)
        if not output.strip():
            return [], []
        parsed = csv.reader(io.StringIO(output))
        records = list(parsed)
        if not records:
            return [], []
        columns = records[0]
        rows = [[None if value == NULL_MARKER else value for value in row] for row in records[1:]]
        return columns, rows

    def list_tables(self) -> list[tuple[str, str]]:
        sql = """
SELECT c.relname AS table_name,
       GREATEST(c.reltuples::bigint, 0)::text AS estimated_rows
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
ORDER BY lower(c.relname);
"""
        _, rows = self.query(sql)
        return [(str(row[0]), str(row[1])) for row in rows]

    def columns(self, table: str) -> list[Column]:
        if table in self.column_cache:
            return self.column_cache[table]
        sql = f"""
SELECT a.attname,
       format_type(a.atttypid, a.atttypmod),
       NOT a.attnotnull,
       pg_get_expr(ad.adbin, ad.adrelid),
       EXISTS (
         SELECT 1 FROM pg_index i
         WHERE i.indrelid = a.attrelid AND i.indisprimary AND a.attnum = ANY(i.indkey)
       )
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
WHERE n.nspname = 'public' AND c.relname = {quote_text(table)}
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum;
"""
        _, rows = self.query(sql)
        result = [
            Column(str(r[0]), str(r[1]), r[2] == "t", r[3], r[4] == "t")
            for r in rows
        ]
        self.column_cache[table] = result
        return result

    def search_players(self, search: str = "") -> tuple[list[str], list[list[str | None]]]:
        where = ""
        if search.strip():
            needle = search.strip()
            comparisons = [search_predicate(expr, needle) for expr in ('u.id::text', 'u."chipId"', 'u."accessCode"')]
            comparisons.append('EXISTS (SELECT 1 FROM "Car" c WHERE c."userId"=u.id AND ' + search_predicate('c.name', needle) + ')')
            where = "WHERE " + " OR ".join(comparisons)
        return self.query(f'''
SELECT u.id AS "Player ID", u."accessCode" AS "Access code", u."chipId" AS "Card ID",
       u."userBanned" AS "Banned", (SELECT COUNT(*) FROM "Car" c WHERE c."userId"=u.id) AS "Cars"
FROM "User" u {where} ORDER BY u.id DESC LIMIT 200;
''')

    def player_details(self, user_id: str):
        if not user_id.isdecimal():
            raise ValueError("Invalid player ID.")
        user_columns = self.columns("User")
        _, users = self.query(f'SELECT * FROM "User" WHERE id={int(user_id)};')
        if not users:
            raise RuntimeError("This player was removed. Refresh the player list.")
        car_columns = self.columns("Car")
        _, cars = self.query(f'SELECT * FROM "Car" WHERE "userId"={int(user_id)} ORDER BY "carId";')
        return user_columns, users[0], car_columns, cars

    def update_fields(self, table: str, columns: list[Column], original: list[str | None], changes: dict[str, str | None]):
        if not changes:
            return
        indexed = {column.name: (index, column) for index, column in enumerate(columns)}
        unknown = set(changes) - indexed.keys()
        if unknown:
            raise ValueError("Unknown field: " + ", ".join(sorted(unknown)))
        predicate = row_predicate(columns, original)
        assignments = []
        for name, value in changes.items():
            index, column = indexed[name]
            assignments.append(f"{quote_ident(name)}={sql_value(value, column)}")
            # An open dialog must not overwrite a newer value saved by a cabinet.
            predicate += f" AND {quote_ident(name)} IS NOT DISTINCT FROM {sql_value(original[index], column)}"
        _, rows = self.query(f'UPDATE {quote_ident(table)} SET {", ".join(assignments)} WHERE {predicate} RETURNING 1 AS updated;')
        if len(rows) != 1:
            raise RuntimeError("The row changed or was removed since it was loaded. Refresh it before saving again.")

    def delete_records(self, table, columns, rows):
        if not rows:
            return
        predicates = []
        for row in rows:
            predicate = row_predicate(columns, row)
            for index, column in enumerate(columns):
                predicate += f" AND {quote_ident(column.name)} IS NOT DISTINCT FROM {sql_value(row[index], column)}"
            predicates.append("(" + predicate + ")")
        delimiter = "$editor_" + uuid.uuid4().hex + "$"
        # Any stale selected row rolls the entire delete back.
        self.run(f'''BEGIN;
DO {delimiter}
DECLARE affected integer;
BEGIN
DELETE FROM {quote_ident(table)} WHERE {" OR ".join(predicates)};
GET DIAGNOSTICS affected = ROW_COUNT;
IF affected <> {len(rows)} THEN
RAISE EXCEPTION 'A selected row changed or was removed. Refresh before deleting.';
END IF;
END {delimiter};
COMMIT;''')

    def backup(self) -> Path:
        backup_root = self.server_root / "backups"
        backup_root.mkdir(parents=True, exist_ok=True)
        base = backup_root / f"before-db-editor-{datetime.now():%Y%m%d-%H%M%S}.dump"
        output = base
        sequence = 1
        while output.exists():
            output = base.with_name(f"{base.stem}-{sequence}{base.suffix}")
            sequence += 1
        args = [
            str(self.pg_dump), "-h", str(self.settings["host"]),
            "-p", str(self.settings["port"]), "-U", str(self.settings["user"]),
            "-d", str(self.settings["database"]), "--format=custom", f"--file={output}",
        ]
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        result = subprocess.run(
            args, capture_output=True, text=True, encoding="utf-8", errors="replace",
            env=self._environment(), timeout=120, creationflags=flags,
        )
        if result.returncode or not output.is_file() or output.stat().st_size == 0:
            output.unlink(missing_ok=True)
            raise RuntimeError((result.stderr or result.stdout).strip() or "Backup failed")
        return output


class ScrollableForm(ttk.Frame):
    def __init__(self, parent):
        super().__init__(parent)
        import tkinter as tk
        self.canvas = tk.Canvas(self, highlightthickness=0)
        scrollbar = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.body = ttk.Frame(self.canvas, padding=8)
        self.window = self.canvas.create_window((0, 0), window=self.body, anchor="nw")
        self.canvas.configure(yscrollcommand=scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.body.bind("<Configure>", lambda _e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self.window, width=e.width))


class DatabaseEditor:
    def __init__(self, root: Tk, server_root: Path):
        self.root = root
        self.db = BayshoreDatabase(server_root)
        self.server_root = server_root
        self.current_table: str | None = None
        self.current_columns: list[Column] = []
        self.current_rows: list[list[str | None]] = []
        self.table_names: list[tuple[str, str]] = []
        self.offset = 0
        self.write_backup = BooleanVar(value=True)
        self.status = StringVar(value="Connecting...")
        self.table_filter = StringVar()
        self.search_text = StringVar()
        self.page_size = StringVar(value="100")
        self.page_label = StringVar(value="")
        self.total_rows = 0
        self.search_column = StringVar(value="All columns")
        self.search_mode = StringVar(value="Contains")
        self.sort_column: str | None = None
        self.sort_descending = False
        self.busy = False
        self.jobs: queue.Queue = queue.Queue()
        self.disabled_widgets = []
        self.player_search = StringVar()
        self.player_summary = StringVar(value="Select a player to see their cars and account.")
        self.player_results = []
        self.player_original = None
        self.player_columns = []
        self.player_cars = []
        self.car_columns = []
        self.car_selected_row = None
        self.car_values = {name: StringVar() for name, _ in CAR_FIELDS}
        self.player_banned = BooleanVar()
        self.console_write = BooleanVar(value=False)

        root.title(f"Bayshore Database Editor {EDITOR_VERSION}")
        root.geometry("1320x820")
        root.minsize(1050, 680)
        root.option_add("*Font", "{Segoe UI} 10")
        root.protocol("WM_DELETE_WINDOW", self.close)
        self._build_ui()
        self.refresh_tables()

    def _build_ui(self):
        self.root.option_add("*tearOff", False)
        ttk.Label(self.root, text=f"Server: {self.server_root}  |  Database: {self.db.settings['database']}", padding=(10, 8)).pack(fill="x")
        notebook = ttk.Notebook(self.root)
        self.notebook = notebook
        notebook.pack(fill="both", expand=True, padx=8, pady=(8, 4))

        players = ttk.Frame(notebook)
        browser = ttk.Frame(notebook)
        self.browser_tab = browser
        console = ttk.Frame(notebook)
        notebook.add(players, text="Players & cars")
        notebook.add(browser, text="Table browser")
        notebook.add(console, text="SQL console")
        self._build_players(players)

        sidebar = ttk.Frame(browser, padding=(0, 0, 8, 0))
        sidebar.pack(side="left", fill="y")
        ttk.Label(sidebar, text="Tables").pack(anchor="w")
        ttk.Button(sidebar, text="Reload table list", command=self.refresh_tables).pack(fill="x", pady=4)
        filter_entry = ttk.Entry(sidebar, textvariable=self.table_filter, width=28)
        filter_entry.pack(fill="x", pady=(4, 5))
        filter_entry.bind("<KeyRelease>", lambda _e: self._render_table_list())
        self.table_list = ttk.Treeview(sidebar, columns=("rows",), show="tree headings", height=24)
        self.table_list.heading("#0", text="Name")
        self.table_list.heading("rows", text="Est. rows")
        self.table_list.column("#0", width=190)
        self.table_list.column("rows", width=70, anchor="e")
        list_scroll = ttk.Scrollbar(sidebar, orient="vertical", command=self.table_list.yview)
        self.table_list.configure(yscrollcommand=list_scroll.set)
        self.table_list.pack(side="left", fill="y", expand=True)
        list_scroll.pack(side="right", fill="y")
        self.table_list.bind("<<TreeviewSelect>>", self._select_table)

        main = ttk.Frame(browser)
        main.pack(side="left", fill="both", expand=True)
        toolbar = ttk.Frame(main)
        toolbar.pack(fill="x", pady=(0, 6))
        ttk.Button(toolbar, text="Refresh", command=self.load_page).pack(side="left")
        ttk.Button(toolbar, text="Add row", command=self.add_row).pack(side="left", padx=(5, 0))
        ttk.Button(toolbar, text="Delete selected", command=self.delete_rows).pack(side="left", padx=(5, 0))
        ttk.Button(toolbar, text="Export page CSV", command=self.export_page).pack(side="left", padx=(5, 0))
        ttk.Button(toolbar, text="Create backup", command=self.create_backup).pack(side="left", padx=(5, 12))
        ttk.Checkbutton(toolbar, text="Backup before writes", variable=self.write_backup).pack(side="left")
        searchbar = ttk.Frame(main)
        searchbar.pack(fill="x", pady=(0, 6))
        ttk.Label(searchbar, text="Search:").pack(side="left", padx=(0, 4))
        search = ttk.Entry(searchbar, textvariable=self.search_text, width=28)
        search.pack(side="left")
        search.bind("<Return>", lambda _e: self._new_search())
        self.column_picker = ttk.Combobox(searchbar, textvariable=self.search_column, values=("All columns",), width=24, state="readonly")
        self.column_picker.pack(side="left", padx=5)
        self.column_picker.bind("<<ComboboxSelected>>", lambda _e: self._new_search())
        mode_picker = ttk.Combobox(searchbar, textvariable=self.search_mode, values=("Contains", "Exact"), width=9, state="readonly")
        mode_picker.pack(side="left")
        mode_picker.bind("<<ComboboxSelected>>", lambda _e: self._new_search())
        ttk.Button(searchbar, text="Search", command=self._new_search).pack(side="left", padx=(4, 0))
        ttk.Button(searchbar, text="Clear", command=self.clear_search).pack(side="left", padx=4)
        ttk.Label(searchbar, text="Rows:").pack(side="right", padx=(6, 3))
        page_box = ttk.Combobox(searchbar, textvariable=self.page_size, values=("25", "50", "100", "250", "500"), width=5, state="readonly")
        page_box.pack(side="right")
        page_box.bind("<<ComboboxSelected>>", lambda _e: self._new_search())

        grid_frame = ttk.Frame(main)
        grid_frame.pack(fill="both", expand=True)
        self.grid = ttk.Treeview(grid_frame, show="headings", selectmode="extended")
        xscroll = ttk.Scrollbar(grid_frame, orient="horizontal", command=self.grid.xview)
        yscroll = ttk.Scrollbar(grid_frame, orient="vertical", command=self.grid.yview)
        self.grid.configure(xscrollcommand=xscroll.set, yscrollcommand=yscroll.set)
        self.grid.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        grid_frame.rowconfigure(0, weight=1)
        grid_frame.columnconfigure(0, weight=1)
        self.grid.bind("<Double-1>", self.edit_cell)

        pager = ttk.Frame(main)
        pager.pack(fill="x", pady=(5, 0))
        self.previous_button = ttk.Button(pager, text="Previous", command=self.previous_page)
        self.previous_button.pack(side="left")
        self.next_button = ttk.Button(pager, text="Next", command=self.next_page)
        self.next_button.pack(side="left", padx=5)
        ttk.Label(pager, textvariable=self.page_label).pack(side="left", padx=8)
        ttk.Label(pager, text="Double-click a cell to edit it.").pack(side="right")

        self._build_console(console)
        footer = ttk.Frame(self.root)
        footer.pack(fill="x", padx=8, pady=(0, 6))
        statusbar = ttk.Label(footer, textvariable=self.status, anchor="w", padding=(6, 3))
        statusbar.pack(side="left", fill="x", expand=True)
        self.progress = ttk.Progressbar(footer, mode="indeterminate", length=130)
        self.progress.pack(side="right")

    def _build_players(self, parent):
        searchbar = ttk.Frame(parent, padding=10)
        searchbar.pack(fill="x")
        ttk.Label(searchbar, text="Find player:").pack(side="left", padx=(0, 8))
        entry = ttk.Entry(searchbar, textvariable=self.player_search, width=42)
        entry.pack(side="left")
        entry.bind("<Return>", lambda _e: self.search_players())
        ttk.Button(searchbar, text="Search", command=self.search_players).pack(side="left", padx=5)
        ttk.Button(searchbar, text="Show all", command=self.clear_player_search).pack(side="left")
        ttk.Button(searchbar, text="Create backup", command=self.create_backup).pack(side="right")
        ttk.Label(parent, text="Search by car name, player ID, access code, or card ID. Up to 200 players are shown.").pack(anchor="w", padx=10)
        player_frame = ttk.Frame(parent)
        player_frame.pack(fill="x", padx=10, pady=8)
        self.player_grid = ttk.Treeview(player_frame, show="headings", height=6, selectmode="browse")
        player_scroll = ttk.Scrollbar(player_frame, orient="vertical", command=self.player_grid.yview)
        player_horizontal = ttk.Scrollbar(player_frame, orient="horizontal", command=self.player_grid.xview)
        self.player_grid.configure(yscrollcommand=player_scroll.set, xscrollcommand=player_horizontal.set)
        self.player_grid.grid(row=0, column=0, sticky="ew")
        player_scroll.grid(row=0, column=1, sticky="ns")
        player_horizontal.grid(row=1, column=0, sticky="ew")
        player_frame.columnconfigure(0, weight=1)
        self.player_grid.bind("<<TreeviewSelect>>", self.select_player)
        detail = ttk.LabelFrame(parent, text="Selected player", padding=8)
        detail.pack(fill="x", padx=10)
        ttk.Label(detail, textvariable=self.player_summary).pack(side="left", fill="x", expand=True)
        ttk.Checkbutton(detail, text="Banned", variable=self.player_banned).pack(side="left", padx=8)
        ttk.Button(detail, text="Save account", command=self.save_player).pack(side="left", padx=4)
        ttk.Button(detail, text="Copy access code", command=self.copy_access_code).pack(side="left", padx=4)
        body = ttk.Panedwindow(parent, orient="horizontal")
        body.pack(fill="both", expand=True, padx=10, pady=10)
        car_list = ttk.LabelFrame(body, text="Player's cars", padding=8)
        editor = ttk.LabelFrame(body, text="Edit selected car", padding=8)
        body.add(car_list, weight=3)
        body.add(editor, weight=2)
        self.car_grid = ttk.Treeview(car_list, show="headings", selectmode="browse")
        scrollbar = ttk.Scrollbar(car_list, orient="vertical", command=self.car_grid.yview)
        self.car_grid.configure(yscrollcommand=scrollbar.set)
        self.car_grid.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        self.car_grid.bind("<<TreeviewSelect>>", self.select_car)
        form = ScrollableForm(editor)
        form.pack(fill="both", expand=True)
        for index, (name, label) in enumerate(CAR_FIELDS):
            ttk.Label(form.body, text=label).grid(row=index, column=0, sticky="w", padx=(0, 10), pady=4)
            ttk.Entry(form.body, textvariable=self.car_values[name]).grid(row=index, column=1, sticky="ew", pady=4)
        form.body.columnconfigure(1, weight=1)
        controls = ttk.Frame(editor)
        controls.pack(fill="x", pady=(8, 0))
        ttk.Checkbutton(controls, text="Backup before writes", variable=self.write_backup).pack(anchor="w")
        buttons = ttk.Frame(controls)
        buttons.pack(fill="x", pady=5)
        ttk.Button(buttons, text="Save car", command=self.save_car).pack(side="left")
        ttk.Button(buttons, text="Reset form", command=self.reset_car_form).pack(side="left", padx=5)
        ttk.Button(buttons, text="All car fields", command=self.open_car_table).pack(side="left")

    def _run_task(self, description, work, done):
        if self.busy:
            return False
        self.busy = True
        self._set_status(description)
        self.root.configure(cursor="watch")
        self.progress.start(15)
        self.disabled_widgets = []
        def disable(parent):
            for widget in parent.winfo_children():
                if isinstance(widget, (ttk.Button, ttk.Checkbutton, ttk.Combobox, ttk.Entry, ttk.Treeview)):
                    self.disabled_widgets.append((widget, "disabled" in widget.state()))
                    widget.state(["disabled"])
                disable(widget)
        disable(self.root)
        def execute():
            try:
                self.jobs.put((done, work(), None))
            except Exception as exc:
                self.jobs.put((done, None, exc))
        threading.Thread(target=execute, daemon=True).start()
        self.root.after(40, self._poll_task)
        return True

    def _poll_task(self):
        try:
            done, result, error = self.jobs.get_nowait()
        except queue.Empty:
            self.root.after(40, self._poll_task)
            return
        self.busy = False
        self.root.configure(cursor="")
        self.progress.stop()
        for widget, was_disabled in self.disabled_widgets:
            if widget.winfo_exists() and not was_disabled:
                widget.state(["!disabled"])
        # Pagination buttons may have been disabled on an earlier page.
        self.previous_button.state(["!disabled"] if self.offset else ["disabled"])
        self.next_button.state(["!disabled"] if self.offset + len(self.current_rows) < self.total_rows else ["disabled"])
        if error:
            self._error("Database operation failed", error)
            return
        try:
            done(result)
        except Exception as exc:
            self._error("Could not display result", exc)

    def _car_changes(self):
        if self.car_selected_row is None:
            return {}
        original = dict(zip((c.name for c in self.car_columns), self.car_selected_row))
        return {name: value.get() for name, value in self.car_values.items() if name in original and value.get() != (original[name] or "")}

    def _confirm_discard(self):
        account_changed = False
        if self.player_original is not None:
            original = dict(zip((c.name for c in self.player_columns), self.player_original))
            account_changed = self.player_banned.get() != (original.get("userBanned") == "t")
        return not (self._car_changes() or account_changed) or messagebox.askyesno("Unsaved changes", "Discard the unsaved player/car changes?", parent=self.root)

    def search_players(self):
        if self.busy or not self._confirm_discard():
            return
        search = self.player_search.get()
        def display(result):
            columns, rows = result
            self.player_results = rows
            self.player_original = None
            self.car_selected_row = None
            self.player_cars = []
            self.reset_car_form()
            self.player_banned.set(False)
            self.player_summary.set("Select a player to see their cars and account.")
            self._fill_grid(self.player_grid, columns, rows)
            self._fill_grid(self.car_grid, ["Car ID", "Name", "Title", "Power", "Handling"], [])
            self._set_status(f"{len(rows)} players shown. Search to narrow the list." if len(rows) == 200 else f"Found {len(rows)} player(s).")
        self._run_task("Finding players...", lambda: self.db.search_players(search), display)

    def clear_player_search(self):
        self.player_search.set("")
        self.search_players()

    def select_player(self, _event=None):
        if self.busy or not self.player_grid.selection():
            return
        index = int(self.player_grid.selection()[0])
        user_id = self.player_results[index][0]
        if self.player_original is not None:
            original = dict(zip((c.name for c in self.player_columns), self.player_original))
            if original.get("id") == user_id:
                return
        if not self._confirm_discard():
            self.player_grid.selection_remove(*self.player_grid.selection())
            return
        def display(result):
            self.player_columns, self.player_original, self.car_columns, self.player_cars = result
            user = dict(zip((c.name for c in self.player_columns), self.player_original))
            self.player_summary.set(f"Player {user['id']}  |  Access code: {user['accessCode']}  |  {len(self.player_cars)} car(s)")
            self.player_banned.set(user.get("userBanned") == "t")
            self.car_selected_row = None
            self.reset_car_form()
            names = [c.name for c in self.car_columns]
            rows = [[row[names.index(name)] for name in ("carId", "name", "title", "tunePower", "tuneHandling")] for row in self.player_cars]
            self._fill_grid(self.car_grid, ["Car ID", "Name", "Title", "Power", "Handling"], rows)
            if rows:
                self.car_grid.selection_set("0")
            self._set_status(f"Player {user_id} loaded. Edit the form and save when ready.")
        self._run_task("Loading player and cars...", lambda: self.db.player_details(str(user_id)), display)

    def select_car(self, _event=None):
        if self.busy or not self.car_grid.selection():
            return
        row = self.player_cars[int(self.car_grid.selection()[0])]
        if row is self.car_selected_row:
            return
        if self._car_changes() and not messagebox.askyesno("Unsaved car changes", "Discard the unsaved car changes?", parent=self.root):
            self.car_grid.selection_remove(*self.car_grid.selection())
            return
        self.car_selected_row = row
        self.reset_car_form()

    def reset_car_form(self):
        values = dict(zip((c.name for c in self.car_columns), self.car_selected_row or []))
        for name, variable in self.car_values.items():
            variable.set(values.get(name) or "")

    def _save_record(self, table, columns, original, changes, dialog=None, after=None):
        if self.busy:
            return
        if not changes:
            messagebox.showinfo("No changes", "There are no changes to save.", parent=dialog or self.root)
            return
        try:
            schema = {c.name: c for c in columns}
            for name, value in changes.items():
                column = schema[name]
                sql_value(value, column)
                if value is not None and column.pg_type in {"integer", "bigint", "smallint"}:
                    if not re.fullmatch(r"[+-]?\d+", value.strip()):
                        raise ValueError(f"{name} must be a whole number.")
            preview = "\n".join(f"{name}: {value!r}" for name, value in changes.items())
            if not messagebox.askyesno("Confirm changes", f"Save these {table} changes?\n\n{preview}", parent=dialog or self.root):
                return
            backup_enabled = self.write_backup.get()
            def work():
                backup = self.db.backup() if backup_enabled else None
                self.db.update_fields(table, columns, original, changes)
                return backup
            def complete(backup):
                for index, column in enumerate(columns):
                    if column.name in changes:
                        value = changes[column.name]
                        original[index] = ("t" if value == "true" else "f") if column.pg_type == "boolean" and value is not None else value
                if dialog:
                    dialog.destroy()
                if after:
                    after()
                self._set_status(f"Saved {len(changes)} {table} field(s)." + (f" Backup: {backup.name}" if backup else ""))
            self._run_task("Backing up and saving changes..." if backup_enabled else "Saving changes...", work, complete)
        except Exception as exc:
            self._error("Cannot save", exc)

    def save_car(self):
        if self.car_selected_row is None:
            messagebox.showinfo("Select a car", "Select a player and car first.", parent=self.root)
            return
        changes = self._car_changes()
        for name, value in changes.items():
            if name not in {"name", "title"} and re.fullmatch(r"[+-]?\d+", value.strip()) and int(value) < 0:
                messagebox.showerror("Invalid car value", f"{name} cannot be negative in the car form.", parent=self.root)
                return
        def display():
            names = [c.name for c in self.car_columns]
            rows = [[row[names.index(name)] for name in ("carId", "name", "title", "tunePower", "tuneHandling")] for row in self.player_cars]
            selected = str(self.player_cars.index(self.car_selected_row))
            self._fill_grid(self.car_grid, ["Car ID", "Name", "Title", "Power", "Handling"], rows)
            self.car_grid.selection_set(selected)
            self.reset_car_form()
        self._save_record("Car", self.car_columns, self.car_selected_row, changes, after=display)

    def save_player(self):
        if self.player_original is None:
            messagebox.showinfo("Select a player", "Select a player first.", parent=self.root)
            return
        original = dict(zip((c.name for c in self.player_columns), self.player_original))
        changed = self.player_banned.get() != (original.get("userBanned") == "t")
        def display():
            for index, row in enumerate(self.player_results):
                if row[0] == original.get("id"):
                    row[3] = "t" if self.player_banned.get() else "f"
                    self.player_grid.set(str(index), "Banned", row[3])
        self._save_record("User", self.player_columns, self.player_original, {"userBanned": "true" if self.player_banned.get() else "false"} if changed else {}, after=display)

    def copy_access_code(self):
        if self.player_original is not None:
            values = dict(zip((c.name for c in self.player_columns), self.player_original))
            self.root.clipboard_clear()
            self.root.clipboard_append(values["accessCode"])
            self._set_status("Access code copied.")

    def open_car_table(self):
        if self.car_selected_row is None or self.busy:
            return
        if not self._confirm_discard():
            return
        values = dict(zip((c.name for c in self.car_columns), self.car_selected_row))
        self.current_table = "Car"
        self.offset = 0
        self.search_text.set(values["carId"])
        self.search_column.set("carId")
        self.search_mode.set("Exact")
        self.sort_column = None
        self.notebook.select(self.browser_tab)
        self.load_page()

    def close(self):
        if self.busy:
            messagebox.showinfo("Operation running", "Wait for the database operation to finish before closing.", parent=self.root)
            return
        if self._confirm_discard():
            self.root.destroy()

    def _close_dialog(self, dialog):
        if self.busy:
            messagebox.showinfo("Operation running", "Wait for the save to finish before closing this dialog.", parent=dialog)
        else:
            dialog.destroy()

    def _build_console(self, parent):
        warning = "Advanced: one SQL statement at a time. Read-only by default. Enable writes explicitly to modify data."
        ttk.Label(parent, text=warning, foreground="#9a5b00").pack(anchor="w", padx=8, pady=(8, 4))
        self.sql_text = Text(parent, height=9, wrap="none", undo=True)
        self.sql_text.pack(fill="x", padx=8)
        self.sql_text.insert("1.0", 'SELECT * FROM "User" ORDER BY id LIMIT 100;')
        actions = ttk.Frame(parent)
        actions.pack(fill="x", padx=8, pady=5)
        ttk.Button(actions, text="Run SQL", command=self.run_console_sql).pack(side="left")
        ttk.Checkbutton(actions, text="Allow writes", variable=self.console_write).pack(side="left", padx=10)
        ttk.Checkbutton(actions, text="Backup before writes", variable=self.write_backup).pack(side="left", padx=10)
        self.console_grid = ttk.Treeview(parent, show="headings")
        cx = ttk.Scrollbar(parent, orient="horizontal", command=self.console_grid.xview)
        cy = ttk.Scrollbar(parent, orient="vertical", command=self.console_grid.yview)
        self.console_grid.configure(xscrollcommand=cx.set, yscrollcommand=cy.set)
        self.console_grid.pack(fill="both", expand=True, padx=(8, 24))
        cy.place(relx=1.0, x=-24, y=183, relheight=0.68)
        cx.pack(fill="x", padx=(8, 24), pady=(0, 8))

    def _set_status(self, text: str):
        self.status.set(text)
        self.root.update_idletasks()

    def _error(self, title: str, exc: Exception):
        self._set_status(f"Error: {exc}")
        messagebox.showerror(title, str(exc), parent=self.root)

    def refresh_tables(self):
        initial = not self.table_names
        def display(tables):
            self.table_names = tables
            self._render_table_list()
            self._set_status(f"Connected to {self.db.settings['database']} on {self.db.settings['host']}:{self.db.settings['port']}")
            if initial:
                self.search_players()
        self._run_task("Connecting to Bayshore...", self.db.list_tables, display)

    def _render_table_list(self):
        selected = self.current_table
        self.table_list.delete(*self.table_list.get_children())
        needle = self.table_filter.get().strip().casefold()
        for table, rows in self.table_names:
            if needle and needle not in table.casefold():
                continue
            iid = self.table_list.insert("", END, text=table, values=(rows,))
            if table == selected:
                self.table_list.selection_set(iid)

    def _select_table(self, _event=None):
        if self.busy:
            return
        selected = self.table_list.selection()
        if not selected:
            return
        table = self.table_list.item(selected[0], "text")
        if table == self.current_table:
            return
        self.current_table = table
        self.offset = 0
        self.search_text.set("")
        self.search_column.set("All columns")
        self.search_mode.set("Contains")
        self.sort_column = None
        self.load_page()

    def load_page(self):
        if not self.current_table or self.busy:
            return
        table = self.current_table
        limit = int(self.page_size.get())
        search, search_column = self.search_text.get().strip(), self.search_column.get()
        exact = self.search_mode.get() == "Exact"
        sort, descending, offset = self.sort_column, self.sort_descending, self.offset
        def work():
            schema = self.db.columns(table)
            names = [c.name for c in schema]
            keys = [c.name for c in schema if c.primary_key]
            ordering = ([sort] if sort in names else []) + [name for name in keys if name != sort]
            order = " ORDER BY " + ", ".join(f"t.{quote_ident(name)}" + (" DESC" if name == sort and descending else " ASC") for name in ordering) if ordering else ""
            table_id = quote_ident(table)
            expression = f"CAST(t.{quote_ident(search_column)} AS text)" if search_column in names else "CAST(t AS text)"
            where = (" WHERE " + (expression + " = " + quote_text(search) if exact else search_predicate(expression, search))) if search else ""
            count_cols, count_rows = self.db.query(f"SELECT COUNT(*) AS count FROM {table_id} t{where};")
            total = int(count_rows[0][0]) if count_cols and count_rows else 0
            actual_offset = min(offset, ((total - 1) // limit) * limit) if total else 0
            columns, rows = self.db.query(
                f"SELECT t.* FROM {table_id} t{where}{order} LIMIT {limit} OFFSET {actual_offset};"
            )
            return schema, columns, rows, total, actual_offset
        def display(result):
            self.current_columns, columns, rows, total, self.offset = result
            self.total_rows = total
            self.current_rows = rows
            self.column_picker["values"] = ["All columns"] + columns
            if self.search_column.get() not in self.column_picker["values"]:
                self.search_column.set("All columns")
            self._fill_grid(self.grid, columns, rows)
            for name in columns:
                marker = " (descending)" if name == sort and descending else " (ascending)" if name == sort else ""
                self.grid.heading(name, text=name + marker, command=lambda column=name: self.sort_by(column))
            first = self.offset + 1 if rows else 0
            last = self.offset + len(rows) if rows else 0
            self.page_label.set(f"{first}-{last} of {total}")
            self.previous_button.state(["!disabled"] if self.offset else ["disabled"])
            self.next_button.state(["!disabled"] if last < total else ["disabled"])
            pks = [c for c in self.current_columns if c.primary_key]
            pk_names = ", ".join(c.name for c in pks) or "none (editing disabled)"
            self._set_status(f"{table}: {total} matching rows | primary key: {pk_names} | click a heading to sort")
        self._run_task(f"Loading {table}...", work, display)

    def sort_by(self, column):
        if self.busy:
            return
        self.sort_descending = not self.sort_descending if self.sort_column == column else False
        self.sort_column = column
        self.offset = 0
        self.load_page()

    def clear_search(self):
        if self.busy:
            return
        self.search_text.set("")
        self.search_column.set("All columns")
        self.search_mode.set("Contains")
        self._new_search()

    def export_page(self):
        if self.busy or not self.current_table:
            return
        destination = filedialog.asksaveasfilename(parent=self.root, title="Export displayed page", defaultextension=".csv", initialfile=f"{self.current_table}-page.csv", filetypes=[("CSV files", "*.csv")])
        if not destination:
            return
        try:
            with open(destination, "w", encoding="utf-8-sig", newline="") as output:
                writer = csv.writer(output)
                writer.writerow([c.name for c in self.current_columns])
                writer.writerows(self.current_rows)
            self._set_status(f"Exported {len(self.current_rows)} displayed row(s) to {destination}. NULL cells are empty in CSV.")
        except Exception as exc:
            self._error("Export failed", exc)

    @staticmethod
    def _fill_grid(grid: ttk.Treeview, columns: list[str], rows: list[list[str | None]]):
        grid.delete(*grid.get_children())
        grid["columns"] = columns
        for index, column in enumerate(columns):
            grid.heading(column, text=column)
            length = max([len(column)] + [len(str(row[index] or "")) for row in rows[:25]])
            grid.column(column, width=max(90, min(300, length * 8 + 24)), stretch=False)
        for index, row in enumerate(rows):
            values = ["⟨NULL⟩" if value is None else value for value in row]
            grid.insert("", END, iid=str(index), values=values)

    def _new_search(self):
        if self.busy:
            return
        self.offset = 0
        self.load_page()

    def previous_page(self):
        if self.busy:
            return
        self.offset = max(0, self.offset - int(self.page_size.get()))
        self.load_page()

    def next_page(self):
        if not self.busy and self.offset + len(self.current_rows) < self.total_rows:
            self.offset += int(self.page_size.get())
            self.load_page()

    def _sql_value(self, value: str | None, column: Column) -> str:
        return sql_value(value, column)

    def _row_predicate(self, row: list[str | None]) -> str:
        return row_predicate(self.current_columns, row)

    def edit_cell(self, event):
        if not self.current_table or self.busy:
            return
        if not any(c.primary_key for c in self.current_columns):
            messagebox.showinfo("View-only table", "This table has no primary key and cannot be edited.", parent=self.root)
            return
        item = self.grid.identify_row(event.y)
        column_token = self.grid.identify_column(event.x)
        if not item or not column_token:
            return
        column_index = int(column_token[1:]) - 1
        row_index = int(item)
        if column_index < 0 or column_index >= len(self.current_columns) or row_index >= len(self.current_rows):
            return
        column = self.current_columns[column_index]
        original_row = self.current_rows[row_index]
        old_value = original_row[column_index]
        table, schema = self.current_table, self.current_columns

        dialog = Toplevel(self.root)
        dialog.title(f"Edit {self.current_table}.{column.name}")
        dialog.geometry("620x300")
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.protocol("WM_DELETE_WINDOW", lambda: self._close_dialog(dialog))
        ttk.Label(dialog, text=f"Column: {column.name}    Type: {column.pg_type}").pack(anchor="w", padx=10, pady=(10, 4))
        value_box = Text(dialog, height=9, wrap="word")
        value_box.pack(fill="both", expand=True, padx=10, pady=4)
        if old_value is not None:
            value_box.insert("1.0", old_value)
        null_value = BooleanVar(value=old_value is None)
        null_toggle = ttk.Checkbutton(dialog, text="Set SQL NULL", variable=null_value)
        null_toggle.pack(anchor="w", padx=10)
        if not column.nullable:
            null_toggle.state(["disabled"])
        buttons = ttk.Frame(dialog)
        buttons.pack(fill="x", padx=10, pady=10)

        def save():
            new_value = None if null_value.get() else value_box.get("1.0", "end-1c")
            if new_value == old_value:
                dialog.destroy()
                return
            self._save_record(table, schema, original_row, {column.name: new_value}, dialog=dialog, after=self.load_page)

        ttk.Button(buttons, text="Save", command=save).pack(side="right")
        ttk.Button(buttons, text="Cancel", command=dialog.destroy).pack(side="right", padx=6)
        value_box.focus_set()

    def add_row(self):
        if not self.current_table or not self.current_columns or self.busy:
            return
        if not any(c.primary_key for c in self.current_columns):
            messagebox.showinfo("View-only table", "This table has no primary key and cannot be edited.", parent=self.root)
            return
        table = self.current_table
        dialog = Toplevel(self.root)
        dialog.title(f"Add row to {self.current_table}")
        dialog.geometry("760x620")
        dialog.transient(self.root)
        dialog.grab_set()
        dialog.protocol("WM_DELETE_WINDOW", lambda: self._close_dialog(dialog))
        ttk.Label(dialog, text="Enable the fields to include. Disabled fields use their database default.").pack(anchor="w", padx=10, pady=(10, 4))
        form = ScrollableForm(dialog)
        form.pack(fill="both", expand=True, padx=8)
        fields: list[tuple[Column, BooleanVar, StringVar]] = []
        for row_no, column in enumerate(self.current_columns):
            required = not column.nullable and column.default is None
            enabled = BooleanVar(value=required)
            value = StringVar()
            ttk.Checkbutton(form.body, variable=enabled).grid(row=row_no, column=0, padx=3, pady=3)
            ttk.Label(form.body, text=column.name, width=28).grid(row=row_no, column=1, sticky="w", padx=3)
            ttk.Label(form.body, text=column.pg_type, width=22).grid(row=row_no, column=2, sticky="w", padx=3)
            ttk.Entry(form.body, textvariable=value, width=45).grid(row=row_no, column=3, sticky="ew", padx=3)
            fields.append((column, enabled, value))
        form.body.columnconfigure(3, weight=1)
        actions = ttk.Frame(dialog)
        actions.pack(fill="x", padx=10, pady=10)

        def insert():
            try:
                included = [(c, v.get()) for c, enabled, v in fields if enabled.get()]
                if included:
                    names = ", ".join(quote_ident(c.name) for c, _ in included)
                    values = ", ".join(self._sql_value(v, c) for c, v in included)
                    sql = f"INSERT INTO {quote_ident(table)} ({names}) VALUES ({values});"
                else:
                    sql = f"INSERT INTO {quote_ident(table)} DEFAULT VALUES;"
            except Exception as exc:
                self._error("Invalid new row", exc)
                return
            if not messagebox.askyesno("Confirm insert", f"Insert a new row into {self.current_table}?", parent=dialog):
                return
            backup_enabled = self.write_backup.get()
            def work():
                backup = self.db.backup() if backup_enabled else None
                self.db.run("BEGIN;\n" + sql + "\nCOMMIT;")
                return backup
            def complete(backup):
                dialog.destroy()
                self.load_page()
                suffix = f" Backup: {backup.name}" if backup else ""
                self._set_status(f"Inserted row into {table}.{suffix}")
            self._run_task("Backing up and inserting row...", work, complete)

        ttk.Button(actions, text="Insert", command=insert).pack(side="right")
        ttk.Button(actions, text="Cancel", command=dialog.destroy).pack(side="right", padx=6)

    def delete_rows(self):
        if self.busy:
            return
        selected = self.grid.selection()
        if not selected or not self.current_table:
            messagebox.showinfo("Delete row", "Select one or more rows first.", parent=self.root)
            return
        rows = [self.current_rows[int(item)] for item in selected]
        try:
            for row in rows:
                self._row_predicate(row)
        except Exception as exc:
            self._error("Delete unavailable", exc)
            return
        if not messagebox.askyesno(
            "Confirm delete",
            f"Permanently delete {len(rows)} row(s) from {self.current_table}?\n\nRelated rows may also be affected by database constraints.",
            icon="warning", parent=self.root,
        ):
            return
        table, schema, backup_enabled = self.current_table, self.current_columns, self.write_backup.get()
        def work():
            backup = self.db.backup() if backup_enabled else None
            self.db.delete_records(table, schema, rows)
            return backup
        def complete(backup):
            self.load_page()
            suffix = f" Backup: {backup.name}" if backup else ""
            self._set_status(f"Deleted {len(rows)} row(s) from {table}.{suffix}")
        self._run_task("Backing up and deleting selected rows...", work, complete)

    def create_backup(self):
        def complete(backup):
            self._set_status(f"Backup created: {backup}")
            messagebox.showinfo("Backup complete", f"Created:\n{backup}", parent=self.root)
        self._run_task("Creating database backup...", self.db.backup, complete)

    def run_console_sql(self):
        if self.busy:
            return
        sql = self.sql_text.get("1.0", "end-1c").strip()
        if not sql:
            return
        try:
            sql = single_statement(sql)
            read_only = not self.console_write.get()
            if read_only:
                def display(result):
                    columns, rows = result
                    self._fill_grid(self.console_grid, columns, rows)
                    self._set_status(f"Read-only SQL completed: {len(rows)} row(s) returned.")
                self._run_task("Running read-only SQL...", lambda: self.db.query("BEGIN TRANSACTION READ ONLY;\n" + sql + "\n;COMMIT;"), display)
            else:
                if not messagebox.askyesno(
                    "Confirm SQL write",
                    "This SQL may modify the Bayshore database. Execute it?",
                    icon="warning", parent=self.root,
                ):
                    return
                backup_enabled = self.write_backup.get()
                def work():
                    backup = self.db.backup() if backup_enabled else None
                    output = self.db.run("BEGIN;\n" + sql + "\n;COMMIT;")
                    self.db.column_cache.clear()
                    return output, backup
                def display(result):
                    output, backup = result
                    self._fill_grid(self.console_grid, ["Result"], [[output.strip() or "Command completed"]])
                    # Discard loaded snapshots after arbitrary SQL to require a refresh.
                    self.player_original = None
                    self.car_selected_row = None
                    self.player_cars = []
                    self.reset_car_form()
                    self.player_summary.set("Database changed. Refresh the player list before editing.")
                    self._fill_grid(self.car_grid, ["Car ID", "Name", "Title", "Power", "Handling"], [])
                    self.current_rows = []
                    self._fill_grid(self.grid, [], [])
                    suffix = f" Backup: {backup.name}" if backup else ""
                    self._set_status(f"SQL write completed. Refresh any open table or player list.{suffix}")
                self._run_task("Backing up and running SQL write...", work, display)
        except Exception as exc:
            self._error("SQL failed", exc)


def find_server_root(package_root: Path | None = None) -> Path:
    script = Path(__file__).resolve()
    base = package_root or script.parent.parent
    candidates = [base, base / "server"]
    if package_root is None:
        candidates.extend([Path.cwd(), Path.cwd() / "server"])
    for candidate in candidates:
        if (candidate / ".env").is_file() and (candidate / ".runtime").is_dir():
            return candidate
    raise RuntimeError("Could not locate a configured Bayshore server. Select the folder containing its .env and .runtime.")


def main():
    root = Tk()
    try:
        style = ttk.Style(root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        try:
            server_root = find_server_root()
        except RuntimeError:
            chosen = filedialog.askdirectory(parent=root, title="Select configured Bayshore server folder")
            if not chosen:
                root.destroy()
                return
            server_root = find_server_root(Path(chosen))
        DatabaseEditor(root, server_root)
    except Exception as exc:
        messagebox.showerror("Bayshore Database Editor", str(exc), parent=root)
        root.destroy()
        return
    root.mainloop()


if __name__ == "__main__":
    main()

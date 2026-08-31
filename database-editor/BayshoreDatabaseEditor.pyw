"""Dependency-free graphical PostgreSQL editor for a local Bayshore server."""

from __future__ import annotations

import csv
import io
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tkinter import BooleanVar, END, StringVar, Text, Tk, Toplevel, messagebox
from tkinter import ttk
from urllib.parse import unquote, urlparse


NULL_MARKER = "__BAYSHORE_DATABASE_EDITOR_NULL_7D3A9C__"


def quote_ident(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def quote_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


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

    @staticmethod
    def _read_settings(env_path: Path) -> dict[str, object]:
        if not env_path.is_file():
            raise RuntimeError(f"Bayshore configuration was not found: {env_path}")
        match = re.search(r"(?m)^POSTGRES_URL=(.+?)\s*$", env_path.read_text(encoding="utf-8"))
        if not match:
            raise RuntimeError("POSTGRES_URL is missing from .env")
        parsed = urlparse(match.group(1).strip())
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
        return [
            Column(str(r[0]), str(r[1]), r[2] == "t", r[3], r[4] == "t")
            for r in rows
        ]

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

        root.title("Bayshore Database Editor")
        root.geometry("1280x760")
        root.minsize(900, 560)
        self._build_ui()
        self.refresh_tables()

    def _build_ui(self):
        self.root.option_add("*tearOff", False)
        notebook = ttk.Notebook(self.root)
        notebook.pack(fill="both", expand=True, padx=8, pady=(8, 4))

        browser = ttk.Frame(notebook)
        console = ttk.Frame(notebook)
        notebook.add(browser, text="Table browser")
        notebook.add(console, text="SQL console")

        sidebar = ttk.Frame(browser, padding=(0, 0, 8, 0))
        sidebar.pack(side="left", fill="y")
        ttk.Label(sidebar, text="Tables").pack(anchor="w")
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
        ttk.Button(toolbar, text="Delete row", command=self.delete_rows).pack(side="left", padx=(5, 0))
        ttk.Button(toolbar, text="Create backup", command=self.create_backup).pack(side="left", padx=(5, 12))
        ttk.Checkbutton(toolbar, text="Backup before writes", variable=self.write_backup).pack(side="left")
        ttk.Label(toolbar, text="Search:").pack(side="left", padx=(14, 4))
        search = ttk.Entry(toolbar, textvariable=self.search_text, width=22)
        search.pack(side="left")
        search.bind("<Return>", lambda _e: self._new_search())
        ttk.Button(toolbar, text="Apply", command=self._new_search).pack(side="left", padx=(4, 0))
        ttk.Label(toolbar, text="Rows:").pack(side="right", padx=(6, 3))
        page_box = ttk.Combobox(toolbar, textvariable=self.page_size, values=("25", "50", "100", "250", "500"), width=5, state="readonly")
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
        ttk.Button(pager, text="Previous", command=self.previous_page).pack(side="left")
        ttk.Button(pager, text="Next", command=self.next_page).pack(side="left", padx=5)
        ttk.Label(pager, textvariable=self.page_label).pack(side="left", padx=8)
        ttk.Label(pager, text="Double-click a cell to edit it.").pack(side="right")

        self._build_console(console)
        statusbar = ttk.Label(self.root, textvariable=self.status, relief="sunken", anchor="w", padding=(6, 3))
        statusbar.pack(fill="x", padx=8, pady=(0, 6))

    def _build_console(self, parent):
        warning = "Advanced: run one SQL statement at a time. Writes require confirmation. Avoid editing while game clients are saving."
        ttk.Label(parent, text=warning, foreground="#9a5b00").pack(anchor="w", padx=8, pady=(8, 4))
        self.sql_text = Text(parent, height=9, wrap="none", undo=True)
        self.sql_text.pack(fill="x", padx=8)
        self.sql_text.insert("1.0", 'SELECT * FROM "User" ORDER BY id LIMIT 100;')
        actions = ttk.Frame(parent)
        actions.pack(fill="x", padx=8, pady=5)
        ttk.Button(actions, text="Run SQL", command=self.run_console_sql).pack(side="left")
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
        try:
            self._set_status("Loading database tables...")
            self.table_names = self.db.list_tables()
            self._render_table_list()
            self._set_status(f"Connected to {self.db.settings['database']} on {self.db.settings['host']}:{self.db.settings['port']}")
        except Exception as exc:
            self._error("Could not load tables", exc)

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
        selected = self.table_list.selection()
        if not selected:
            return
        table = self.table_list.item(selected[0], "text")
        if table == self.current_table:
            return
        self.current_table = table
        self.offset = 0
        self.search_text.set("")
        self.load_page()

    def _where_clause(self) -> str:
        search = self.search_text.get().strip()
        if not search:
            return ""
        return f" WHERE CAST(t AS text) ILIKE {quote_text('%' + search + '%')}"

    def load_page(self):
        if not self.current_table:
            return
        try:
            self._set_status(f"Loading {self.current_table}...")
            self.current_columns = self.db.columns(self.current_table)
            pks = [c for c in self.current_columns if c.primary_key]
            order = ""
            if pks:
                order = " ORDER BY " + ", ".join(f"t.{quote_ident(c.name)}" for c in pks)
            limit = int(self.page_size.get())
            table_id = quote_ident(self.current_table)
            where = self._where_clause()
            count_cols, count_rows = self.db.query(f"SELECT COUNT(*) AS count FROM {table_id} t{where};")
            total = int(count_rows[0][0]) if count_cols and count_rows else 0
            columns, rows = self.db.query(
                f"SELECT t.* FROM {table_id} t{where}{order} LIMIT {limit} OFFSET {self.offset};"
            )
            self.current_rows = rows
            self._fill_grid(self.grid, columns, rows)
            first = self.offset + 1 if rows else 0
            last = self.offset + len(rows)
            self.page_label.set(f"{first}-{last} of {total}")
            pk_names = ", ".join(c.name for c in pks) or "none (editing disabled)"
            self._set_status(f"{self.current_table}: {total} rows | primary key: {pk_names}")
        except Exception as exc:
            self._error("Could not load table", exc)

    @staticmethod
    def _fill_grid(grid: ttk.Treeview, columns: list[str], rows: list[list[str | None]]):
        grid.delete(*grid.get_children())
        grid["columns"] = columns
        for column in columns:
            grid.heading(column, text=column)
            grid.column(column, width=max(90, min(260, len(column) * 10 + 30)), stretch=False)
        for index, row in enumerate(rows):
            values = ["âŸ¨NULLâŸ©" if value is None else value for value in row]
            grid.insert("", END, iid=str(index), values=values)

    def _new_search(self):
        self.offset = 0
        self.load_page()

    def previous_page(self):
        self.offset = max(0, self.offset - int(self.page_size.get()))
        self.load_page()

    def next_page(self):
        if len(self.current_rows) == int(self.page_size.get()):
            self.offset += int(self.page_size.get())
            self.load_page()

    def _sql_value(self, value: str | None, column: Column) -> str:
        if value is None:
            return "NULL"
        return f"CAST({quote_text(value)} AS {column.pg_type})"

    def _row_predicate(self, row: list[str | None]) -> str:
        pks = [(index, column) for index, column in enumerate(self.current_columns) if column.primary_key]
        if not pks:
            raise RuntimeError("This table has no primary key, so safe editing is disabled.")
        return " AND ".join(
            f"{quote_ident(column.name)} IS NOT DISTINCT FROM {self._sql_value(row[index], column)}"
            for index, column in pks
        )

    def _backup_if_enabled(self) -> Path | None:
        if not self.write_backup.get():
            return None
        self._set_status("Creating safety backup before write...")
        return self.db.backup()

    def edit_cell(self, event):
        if not self.current_table:
            return
        item = self.grid.identify_row(event.y)
        column_token = self.grid.identify_column(event.x)
        if not item or not column_token:
            return
        column_index = int(column_token[1:]) - 1
        row_index = int(item)
        if column_index >= len(self.current_columns) or row_index >= len(self.current_rows):
            return
        column = self.current_columns[column_index]
        original_row = self.current_rows[row_index]
        old_value = original_row[column_index]

        dialog = Toplevel(self.root)
        dialog.title(f"Edit {self.current_table}.{column.name}")
        dialog.geometry("620x300")
        dialog.transient(self.root)
        dialog.grab_set()
        ttk.Label(dialog, text=f"Column: {column.name}    Type: {column.pg_type}").pack(anchor="w", padx=10, pady=(10, 4))
        value_box = Text(dialog, height=9, wrap="word")
        value_box.pack(fill="both", expand=True, padx=10, pady=4)
        if old_value is not None:
            value_box.insert("1.0", old_value)
        null_value = BooleanVar(value=old_value is None)
        ttk.Checkbutton(dialog, text="Set SQL NULL", variable=null_value).pack(anchor="w", padx=10)
        buttons = ttk.Frame(dialog)
        buttons.pack(fill="x", padx=10, pady=10)

        def save():
            new_value = None if null_value.get() else value_box.get("1.0", "end-1c")
            if new_value == old_value:
                dialog.destroy()
                return
            if not messagebox.askyesno(
                "Confirm cell update",
                f"Update {self.current_table}.{column.name}?\n\nOld: {old_value!r}\nNew: {new_value!r}",
                parent=dialog,
            ):
                return
            try:
                backup = self._backup_if_enabled()
                sql = (
                    f"UPDATE {quote_ident(self.current_table)} SET {quote_ident(column.name)} = "
                    f"{self._sql_value(new_value, column)} WHERE {self._row_predicate(original_row)};"
                )
                self.db.run("BEGIN;\n" + sql + "\nCOMMIT;")
                dialog.destroy()
                self.load_page()
                suffix = f" Backup: {backup.name}" if backup else ""
                self._set_status(f"Updated {self.current_table}.{column.name}.{suffix}")
            except Exception as exc:
                self._error("Update failed", exc)

        ttk.Button(buttons, text="Save", command=save).pack(side="right")
        ttk.Button(buttons, text="Cancel", command=dialog.destroy).pack(side="right", padx=6)
        value_box.focus_set()

    def add_row(self):
        if not self.current_table or not self.current_columns:
            return
        dialog = Toplevel(self.root)
        dialog.title(f"Add row to {self.current_table}")
        dialog.geometry("760x620")
        dialog.transient(self.root)
        dialog.grab_set()
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
            included = [(c, v.get()) for c, enabled, v in fields if enabled.get()]
            if included:
                names = ", ".join(quote_ident(c.name) for c, _ in included)
                values = ", ".join(self._sql_value(v, c) for c, v in included)
                sql = f"INSERT INTO {quote_ident(self.current_table)} ({names}) VALUES ({values});"
            else:
                sql = f"INSERT INTO {quote_ident(self.current_table)} DEFAULT VALUES;"
            if not messagebox.askyesno("Confirm insert", f"Insert a new row into {self.current_table}?", parent=dialog):
                return
            try:
                backup = self._backup_if_enabled()
                self.db.run("BEGIN;\n" + sql + "\nCOMMIT;")
                dialog.destroy()
                self.load_page()
                suffix = f" Backup: {backup.name}" if backup else ""
                self._set_status(f"Inserted row into {self.current_table}.{suffix}")
            except Exception as exc:
                self._error("Insert failed", exc)

        ttk.Button(actions, text="Insert", command=insert).pack(side="right")
        ttk.Button(actions, text="Cancel", command=dialog.destroy).pack(side="right", padx=6)

    def delete_rows(self):
        selected = self.grid.selection()
        if not selected or not self.current_table:
            messagebox.showinfo("Delete row", "Select one or more rows first.", parent=self.root)
            return
        rows = [self.current_rows[int(item)] for item in selected]
        try:
            statements = [
                f"DELETE FROM {quote_ident(self.current_table)} WHERE {self._row_predicate(row)};"
                for row in rows
            ]
        except Exception as exc:
            self._error("Delete unavailable", exc)
            return
        if not messagebox.askyesno(
            "Confirm delete",
            f"Permanently delete {len(rows)} row(s) from {self.current_table}?\n\nRelated rows may also be affected by database constraints.",
            icon="warning", parent=self.root,
        ):
            return
        try:
            backup = self._backup_if_enabled()
            self.db.run("BEGIN;\n" + "\n".join(statements) + "\nCOMMIT;")
            self.load_page()
            suffix = f" Backup: {backup.name}" if backup else ""
            self._set_status(f"Deleted {len(rows)} row(s) from {self.current_table}.{suffix}")
        except Exception as exc:
            self._error("Delete failed", exc)

    def create_backup(self):
        try:
            self._set_status("Creating database backup...")
            backup = self.db.backup()
            self._set_status(f"Backup created: {backup}")
            messagebox.showinfo("Backup complete", f"Created:\n{backup}", parent=self.root)
        except Exception as exc:
            self._error("Backup failed", exc)

    def run_console_sql(self):
        sql = self.sql_text.get("1.0", "end-1c").strip()
        if not sql:
            return
        first_word = re.match(r"^\s*([A-Za-z]+)", sql)
        read_only = bool(first_word and first_word.group(1).upper() in {"SELECT", "SHOW", "EXPLAIN", "TABLE", "VALUES"})
        try:
            if read_only:
                self._set_status("Running read-only SQL...")
                columns, rows = self.db.query("BEGIN TRANSACTION READ ONLY;\n" + sql + "\nCOMMIT;")
                self._fill_grid(self.console_grid, columns, rows)
                self._set_status(f"SQL completed: {len(rows)} row(s) returned.")
            else:
                if not messagebox.askyesno(
                    "Confirm SQL write",
                    "This SQL may modify the Bayshore database. Execute it?",
                    icon="warning", parent=self.root,
                ):
                    return
                backup = self._backup_if_enabled()
                output = self.db.run("BEGIN;\n" + sql + "\nCOMMIT;")
                self._fill_grid(self.console_grid, ["Result"], [[output.strip() or "Command completed"]])
                self.refresh_tables()
                if self.current_table:
                    self.load_page()
                suffix = f" Backup: {backup.name}" if backup else ""
                self._set_status(f"SQL write completed.{suffix}")
        except Exception as exc:
            self._error("SQL failed", exc)


def find_server_root() -> Path:
    script = Path(__file__).resolve()
    candidates = [script.parent.parent, Path.cwd()]
    for candidate in candidates:
        if (candidate / ".env").is_file() and (candidate / ".runtime").is_dir():
            return candidate
    raise RuntimeError("Could not locate the Bayshore server root beside the database-editor folder.")


def main():
    root = Tk()
    try:
        style = ttk.Style(root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        DatabaseEditor(root, find_server_root())
    except Exception as exc:
        messagebox.showerror("Bayshore Database Editor", str(exc), parent=root)
        root.destroy()
        return
    root.mainloop()


if __name__ == "__main__":
    main()

"""Read-only smoke test for BayshoreDatabaseEditor.pyw."""

import importlib.machinery
import importlib.util
import csv
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import patch


editor_path = Path(__file__).with_name("BayshoreDatabaseEditor.pyw")
loader = importlib.machinery.SourceFileLoader("bayshore_database_editor", str(editor_path))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = module
loader.exec_module(module)

server_root = module.find_server_root()
database = module.BayshoreDatabase(server_root)
tables = database.list_tables()
assert tables, "No public tables were found"
columns = database.columns("User")
assert any(column.name == "id" and column.primary_key for column in columns)
names, rows = database.query(
    'SELECT id, "carOrder", NULL::text AS null_test FROM "User" ORDER BY id LIMIT 5;'
)
assert names == ["id", "carOrder", "null_test"]
assert all(row[2] is None for row in rows)
print(f"OK: {len(tables)} tables, {len(columns)} User columns, {len(rows)} sample rows")

if "--backup" in sys.argv:
    backup = database.backup()
    assert backup.is_file() and backup.stat().st_size > 0
    print(f"OK: backup created at {backup}")

if "--ui" in sys.argv:
    root = module.Tk()
    root.withdraw()
    editor = module.DatabaseEditor(root, server_root)
    def wait_idle():
        deadline = time.monotonic() + 20
        while editor.busy and time.monotonic() < deadline:
            root.update()
            time.sleep(0.02)
        root.update()
        assert not editor.busy, "Database worker did not finish"
    wait_idle()
    assert len(editor.table_names) == len(tables)
    assert len(editor.notebook.tabs()) == 3
    if editor.player_results:
        editor.player_grid.selection_set("0")
        root.update()
        wait_idle()
        assert editor.player_original is not None
        if editor.player_cars:
            assert editor.car_selected_row is not None
            assert editor.car_values['name'].get()
    editor.current_table = "User"
    editor.load_page()
    wait_idle()
    assert editor.current_columns
    assert editor.total_rows >= len(editor.current_rows)
    editor.sort_by("id")
    wait_idle()
    assert editor.sort_column == "id"
    if editor.current_rows:
        id_index = next(i for i, column in enumerate(editor.current_columns) if column.name == "id")
        player_id = editor.current_rows[0][id_index]
        editor.search_column.set("id")
        editor.search_mode.set("Exact")
        editor.search_text.set(player_id)
        editor._new_search()
        wait_idle()
        assert editor.total_rows == 1
        assert editor.current_rows[0][id_index] == player_id
        with tempfile.TemporaryDirectory(dir=server_root / ".runtime") as folder:
            destination = Path(folder) / "page.csv"
            with patch.object(module.filedialog, "asksaveasfilename", return_value=str(destination)):
                editor.export_page()
            with destination.open(encoding="utf-8-sig", newline="") as exported:
                records = list(csv.reader(exported))
            assert records[0] == [column.name for column in editor.current_columns]
            assert len(records) == 2
    if editor.car_selected_row is not None:
        editor.open_car_table()
        wait_idle()
        assert editor.current_table == "Car" and editor.total_rows == 1
    root.destroy()
    print("OK: async UI, player/car loading, pagination, sorting, exact filters and CSV export")

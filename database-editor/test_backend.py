"""Read-only smoke test for BayshoreDatabaseEditor.pyw."""

import importlib.machinery
import importlib.util
import sys
from pathlib import Path


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
    root.update_idletasks()
    assert len(editor.table_names) == len(tables)
    root.destroy()
    print("OK: Tkinter UI initialized")

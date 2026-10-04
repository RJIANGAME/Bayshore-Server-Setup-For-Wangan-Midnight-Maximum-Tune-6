"""Editor regressions. Live cases use disposable PostgreSQL TEMP tables only."""
import csv
import importlib.machinery
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("editor_regression", str(Path(__file__).with_name("BayshoreDatabaseEditor.pyw")))
spec = importlib.util.spec_from_loader(loader.name, loader)
editor = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = editor
loader.exec_module(editor)


class EditorTests(unittest.TestCase):
    def test_literal_search_does_not_treat_card_symbols_as_wildcards(self):
        expression = editor.search_predicate("name", "50%_O'Brien")
        self.assertIn("50%_O''Brien", expression)
        self.assertNotIn("ILIKE", expression)

    def test_nullable_and_required_fields(self):
        required = editor.Column("name", "text", False, None, False)
        nullable = editor.Column("note", "text", True, None, False)
        with self.assertRaisesRegex(ValueError, "cannot be NULL"):
            editor.sql_value(None, required)
        self.assertEqual("NULL", editor.sql_value(None, nullable))

    def test_console_respects_strings_comments_and_dollar_quotes(self):
        for sql in (
            "SELECT 'a;b'; -- trailing comment",
            'SELECT "semi;colon" FROM example;',
            "WITH q AS (SELECT $$a;b$$) SELECT * FROM q;",
            "/* outer /* nested */ comment */ SELECT $value$a;b$value$;",
            "SELECT E'a\\\';b';",
        ):
            self.assertEqual(sql, editor.single_statement(sql))

    def test_console_rejects_batches_transaction_controls_and_incomplete_sql(self):
        for sql in (
            "SELECT 1; DELETE FROM example;", "SELECT 1;;", "COMMIT;", "-- x\nBEGIN;",
            "SELECT 'not closed", "SELECT $$not closed", "/* not closed", "-- comments only",
            "SELECT '\\'; DELETE FROM example;",
        ):
            with self.assertRaises(ValueError, msg=sql):
                editor.single_statement(sql)

    def test_editor_finds_both_flat_and_packaged_server_layouts(self):
        temp_root = Path(__file__).resolve().parent.parent / ".runtime"
        temp_root.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temp_root) as folder:
            package = Path(folder)
            with self.assertRaises(RuntimeError):
                editor.find_server_root(package)
            server = package / "server"
            server.mkdir()
            (server / ".env").write_text("# fixture", encoding="utf-8")
            (server / ".runtime").mkdir()
            self.assertEqual(server, editor.find_server_root(package))
            self.assertEqual(server, editor.find_server_root(server))


FIXTURE = '''
CREATE TEMP TABLE "EditorFixture" (id integer PRIMARY KEY, label text NOT NULL, enabled boolean NOT NULL, note text);
INSERT INTO "EditorFixture" VALUES (1, 'alpha', true, NULL), (2, 'beta', false, '');
'''
COLUMNS = [
    editor.Column("id", "integer", False, None, True),
    editor.Column("label", "text", False, None, False),
    editor.Column("enabled", "boolean", False, None, False),
    editor.Column("note", "text", True, None, False),
]


class FixtureDatabase(editor.BayshoreDatabase):
    def __init__(self, live):
        self.live = live
        self.last_sql = ""
        self.output = ""

    def query(self, sql):
        self.last_sql = sql
        return self.live.query(FIXTURE + sql)

    def run(self, sql, **_options):
        self.last_sql = sql
        self.output = self.live.run(FIXTURE + sql + '\nSELECT COUNT(*) AS remaining FROM "EditorFixture";', csv_output=True)
        return self.output


@unittest.skipUnless("--live" in sys.argv, "use --live for PostgreSQL TEMP-table checks")
class PostgreSQLTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.live = editor.BayshoreDatabase(editor.find_server_root())

    def test_multi_field_update_and_quoted_car_name(self):
        database = FixtureDatabase(self.live)
        name = "O'Brien; $$ snowman \u2603"
        database.update_fields("EditorFixture", COLUMNS, ["1", "alpha", "t", None], {"label": name, "enabled": "false", "note": ""})
        _, rows = self.live.query(FIXTURE + database.last_sql + '\nSELECT label, enabled, note FROM "EditorFixture" WHERE id=1;')
        self.assertEqual([name, "f", ""], rows[-1])

    def test_stale_update_is_rejected(self):
        database = FixtureDatabase(self.live)
        with self.assertRaisesRegex(RuntimeError, "row changed"):
            database.update_fields("EditorFixture", COLUMNS, ["1", "older label", "t", None], {"label": "new"})

    def test_delete_selected_rows_handles_null_and_empty_values(self):
        database = FixtureDatabase(self.live)
        database.delete_records("EditorFixture", COLUMNS, [["1", "alpha", "t", None], ["2", "beta", "f", ""]])
        self.assertEqual("0", list(csv.reader(io.StringIO(database.output)))[-1][0])

    def test_stale_multi_delete_fails_instead_of_claiming_success(self):
        database = FixtureDatabase(self.live)
        with self.assertRaisesRegex(RuntimeError, "selected row changed"):
            database.delete_records("EditorFixture", COLUMNS, [["1", "alpha", "t", None], ["2", "older label", "f", ""]])

    def test_keyless_table_cannot_be_edited(self):
        database = FixtureDatabase(self.live)
        with self.assertRaisesRegex(RuntimeError, "no primary key"):
            database.update_fields("EditorFixture", COLUMNS[1:], ["alpha", "t", None], {"label": "new"})


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]] + [arg for arg in sys.argv[1:] if arg != "--live"])

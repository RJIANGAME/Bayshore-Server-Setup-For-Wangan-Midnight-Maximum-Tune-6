# Bayshore Database Editor v1.7.0

A dependency-free Windows UI for browsing and carefully editing the local Bayshore PostgreSQL database.

## Start

Double-click `Bayshore-Database-Editor.bat` in the Bayshore server folder.

The editor reads `POSTGRES_URL` from the existing `.env` and uses the bundled PostgreSQL tools. Python 3.10 or newer with Tkinter is required; no `pip install` is needed. It detects both an existing Bayshore root and the release package's nested `server` folder. If neither is configured, select your existing server folder when prompted.

## Players and cars

- Search by car name, player ID, access code, or card ID.
- Select a player to see their cars, copy their access code, or change their account ban flag.
- Select a car to edit its name, title, power/handling tune, tuning points, odometer, VS stars, dress-up progress, and aura together.
- Use **All car fields** to open that exact car in the table browser.
- Review the changes before saving. **Reset form** restores the loaded values; switching away asks before discarding changes.

Database loading, backups, and writes run in the background with a progress indicator. Saves check whether the edited fields have changed since loading and refuse stale changes so newer cabinet values are not overwritten.

## Editing

- Select a table on the left and double-click a cell to edit it.
- Filter all columns or a chosen column using literal **Contains** search or **Exact** matching. Click a column heading to sort; use the page controls to browse results.
- **Export page CSV** exports the displayed page with UTF-8 encoding. NULL and empty strings both export as empty CSV cells; database editing keeps them distinct.
- Use **Add row** or **Delete row** for row-level changes.
- Tables without a primary key are view-only because a row cannot be targeted safely.
- **Backup before writes** is enabled by default. Dumps are saved in `backups` with a `before-db-editor-` prefix.
- The SQL console defaults to a PostgreSQL read-only transaction, including for `WITH` queries. Enable **Allow writes** explicitly to run a write, then confirm it. Run one statement at a time; the editor manages transactions and backs up writes by default.
- Multi-row deletion is atomic and checks the original row values. If a selected row changed, the whole deletion is rolled back.

Avoid editing player rows while game cabinets are actively saving. PostgreSQL constraints remain active, so invalid or unsafe relationship changes will be rejected where the schema protects them.

## Upgrade an existing server

Close the editor, then replace `database-editor` and `Bayshore-Database-Editor.bat` with the copies from the new server ZIP. Keep your existing `.env`, `.runtime`, database, and backups. You do not need to run server setup again or restart Bayshore to update the editor.

## Validation

`python database-editor/test_editor.py --live -v` checks search/SQL parsing, package discovery, and guarded writes using disposable PostgreSQL TEMP tables. `python database-editor/test_backend.py --ui` checks the real schema and asynchronous UI using read-only queries. Neither command edits player saves.

# Bayshore Database Editor

A dependency-free Windows UI for browsing and carefully editing the local Bayshore PostgreSQL database.

## Start

Double-click `Bayshore-Database-Editor.bat` in the Bayshore server folder.

The editor reads `POSTGRES_URL` from the existing `.env` and uses the bundled PostgreSQL tools. Python 3 with Tkinter is required; no `pip install` is needed.

## Editing

- Select a table on the left and double-click a cell to edit it.
- Use **Add row** or **Delete row** for row-level changes.
- Tables without a primary key are view-only because a row cannot be targeted safely.
- **Backup before writes** is enabled by default. Dumps are saved in `backups` with a `before-db-editor-` prefix.
- The SQL console supports advanced queries and asks for confirmation before non-read-only statements.

Avoid editing player rows while game cabinets are actively saving. PostgreSQL constraints remain active, so invalid or unsafe relationship changes will be rejected where the schema protects them.

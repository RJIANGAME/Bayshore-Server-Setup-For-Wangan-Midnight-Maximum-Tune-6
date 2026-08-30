# Bayshore player-data tools

Keep the three root-level BAT files beside the `server-tools` folder in the root of the Bayshore portable server. The tools support both layouts below:

```text
<root>\server\.env
<root>\.env
```

All backups are written to `<root>\backups` as PostgreSQL custom-format `.dump` files.

## Backup

Run `Backup-Player-Data.bat`. PostgreSQL must be installed; the tool starts the portable database when necessary using an isolated `pg_ctl` process, displays progress, and verifies the completed dump before reporting success. A PostgreSQL logical backup is consistent while the server is online.

## Restore (replace)

Run `Restore-Player-Data.bat`, select a `.dump`, and type `RESTORE`. This stops Bayshore, creates a `before-restore-*.dump` safety backup, and atomically replaces the destination database. Existing destination players are removed.

## Merge (preserve current save)

Run `Merge-Player-Data.bat`, select a `.dump`, and type `MERGE`. The tool creates a `before-merge-*.dump`, restores the incoming data into an isolated temporary database, verifies that both databases have the same Bayshore migration set, remaps integer IDs, and imports only card IDs not already present.

The merge imports:

- users and card identity;
- cars, settings, state, GT wings, tuning paths, and car items;
- user items and scratch sheets;
- time-attack records and ghost trails.

For safety, duplicate card IDs remain exactly as they are on the destination. Server-wide crowns, OCM data, rival/battle history, terminal registrations, place/file lists, and global event/ranking records are not imported because they can conflict with destination-wide unique records or other players' car IDs.

After restore or merge, start Bayshore normally and test a known card. Keep the automatically created safety dump until the result has been verified.

> Do not interrupt PostgreSQL, shut down Windows, or start Bayshore while a restore or merge is running.

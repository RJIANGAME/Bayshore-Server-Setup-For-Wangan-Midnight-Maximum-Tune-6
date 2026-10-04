# Bayshore WMMT6 client and server setup v1.7.0

Download **Client Setup** for each player PC and **Server Setup** for the PC hosting Bayshore and MaxiTerminal. Extract the whole package before running its BAT files. Use Japanese WMMT6 1.03.04 with your own game, TeknoParrot, and compatible MaxiTerminal.

## Client

- Cabinet selection 1–4 updates both the actual game's PCB number and AMAuth cabinet ID. Existing Service settings and calibration are preserved and backed up.
- Esc closes the game normally without a false launch-failed message. Actual startup failures and native crashes keep their diagnostics.
- Guided server IP, game, and TeknoParrot selection, unique card identities, and scoped firewall/multicast setup.

## Server and editor

- Complete Bayshore source package with guided database, server, and MaxiTerminal configuration; Node.js 22+ is required.
- Optional Wi-Fi terminal relay addresses and a loss/latency diagnostic. The relay carries terminal heartbeats; race traffic still needs a reliable LAN connection between cabinets.
- Database Editor v1.7.0: Players & Cars search by car name, card ID, access code, or player ID; common car progress fields and account ban editing; direct access to all car fields.
- Responsive background loading/backups/saves, sortable tables, exact/contains filters, pagination, and CSV page export.
- Confirmation and backups enabled by default, stale-value protection, atomic multi-row deletion, and a read-only SQL console unless writes are explicitly enabled. Python 3.10+ with Tkinter is required; no pip packages are needed.
- The editor finds both existing server folders and the release's nested `server` folder.

## Existing installations

Rerun the new client configurator on each PC with a different cabinet number. Keep each PC's own `generated-client-identity.json` to preserve its card identity.

An already configured server does **not** need setup again to update the editor. Close the editor and copy only `database-editor` and `Bayshore-Database-Editor.bat` from the new server ZIP into the existing folder. Preserve `.env`, `.runtime`, player saves, backups, and local terminal configuration. See [Quick start](https://github.com/RJIANGAME/Bayshore-Server-Setup-For-Wangan-Midnight-Maximum-Tune-6/blob/main/QUICK-START.md).

## Validation

Ten editor regression checks passed, with database writes tested only in disposable PostgreSQL TEMP tables. Read-only checks passed against the running database and asynchronous UI, including player/car loading, filters, sorting, and CSV export. Cabinet/launcher PowerShell regression checks passed. A live two-PC race has not been verified; Wi-Fi packet loss and router isolation can still interrupt versus.

Compare downloads with `SHA256SUMS-v1.7.0.txt`. Packages exclude deployment credentials, player identities, database saves/dumps, the game, MaxiTerminal, and OpenParrot. The included compatibility key is the fixed public Project Asakura key; [provenance and hashes](https://github.com/RJIANGAME/Bayshore-Server-Setup-For-Wangan-Midnight-Maximum-Tune-6/blob/main/releases/README.md).

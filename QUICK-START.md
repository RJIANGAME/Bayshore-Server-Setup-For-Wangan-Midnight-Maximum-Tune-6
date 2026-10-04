# WMMT6 LAN setup — v1.7.0

For Japanese WMMT6 1.03.04. Use your own game, TeknoParrot installation, and
compatible MaxiTerminal executable. Keep all PCs on the same LAN. Ethernet
provides the most reliable versus connection.

## Server PC: first setup

1. Install [Node.js LTS](https://nodejs.org/en/download) (22 or newer).
2. Download [Server Setup v1.7.0](https://github.com/RJIANGAME/Bayshore-Server-Setup-For-Wangan-Midnight-Maximum-Tune-6/releases/download/v1.7.0/Bayshore-WMMT6-Server-Setup-v1.7.0.zip), extract it to a permanent folder, and keep the whole folder together.
3. Run `Configure-Server.bat` as administrator. Confirm the detected server IPv4 address. It downloads PostgreSQL, creates the database, installs dependencies, and builds Bayshore.
4. Select your compatible `MaxiTerminal.exe`. Optionally enter stable Wi-Fi cabinet IPs separated by commas for the terminal relay, or press Enter to skip. Setup creates configuration and firewall rules for you.
5. Run `server-terminal-setup\Start-Bayshore-And-Terminal.bat` before starting the clients. Share the server IPv4 address with each player.

Allow internet access during first setup. Node.js installation and providing
MaxiTerminal are required; the package supplies the Bayshore server source and
the setup tools. MaxiTerminal and the game are not redistributed.

## Each player PC

1. Download [Client Setup v1.7.0](https://github.com/RJIANGAME/Bayshore-Server-Setup-For-Wangan-Midnight-Maximum-Tune-6/releases/download/v1.7.0/Bayshore-WMMT6-Client-Setup-v1.7.0.zip) and extract a separate copy on each PC. It includes the four verified client assets.
2. Close WMMT6 and TeknoParrot, then run `client-setup\Configure-Client.bat` as administrator.
3. Enter the server IPv4 address, choose a different cabinet number for each PC, and select `wmn6r.exe` and `TeknoParrotUi.exe`.
4. Launch using `WMMT6-Launch.bat` beside `TeknoParrotUi.exe`. It starts AMAuth directly and fits the game into a centered 16:9 borderless window.
5. Check the game's Service menu shows the chosen cabinet number. Esc closes the launcher normally.

Existing users must rerun the new client configurator on every PC. The old
cabinet selector only set AMAuth; v1.7.0 also sets the actual game PCB number.
Keep your existing `generated-client-identity.json` with that PC's setup folder
when upgrading to preserve its card identity. Never copy it to another cabinet.
Existing Service settings and calibration are preserved and backed up.

| Selected cabinet | Game `mPcbId` | AMAuth `netID` |
|---|---|---|
| 1 | 0 | 1 |
| 2 | 1 | 2 |
| 3 | 2 | 3 |
| 4 | 3 | 4 |

## Daily use and upgrades

Start the server stack, then each client. Stop using
`server-terminal-setup\Stop-Bayshore-And-Terminal.bat` after closing the games.
Only one MaxiTerminal should run on the LAN.

For an existing server, back up saves first and copy the updated
`server-terminal-setup` folder into the existing setup location. Keep its local
`server-terminal.json` and rerun `Configure-Server-Terminal.bat` if you need to
change the relay addresses or refresh its firewall rules. Keep the existing
database and `.env`; extracting a fresh server elsewhere creates a separate
installation and does not move player saves.

## Database editor and existing servers

Install Python 3.10 or newer with Tkinter, then run `Bayshore-Database-Editor.bat`.
The Players & Cars tab searches cards and car names and edits common progress
fields directly. The table browser adds sorting, exact filters, and CSV export.
Backups and saves run in the background; stale saves are refused.

To update only the editor on an already configured server, close the editor and
copy `database-editor` plus `Bayshore-Database-Editor.bat` from the server ZIP into
the existing Bayshore folder. Keep `.env`, `.runtime`, player data, and backups.
There is no need to rerun server setup. See [editor instructions](database-editor/README.md).

## Versus returns to Story Mode

Check unique cabinet numbers first. Test both player PCs on Ethernet on the
same LAN. If Wi-Fi is necessary, avoid guest networks and disable client/AP
isolation in the router settings. Use stable cabinet IPs and rerun setup after
an adapter/IP change.

Run `server-terminal-setup\Check-Multiplayer-Network.bat` on **each player PC**,
entering the other player's address. Packet loss or latency spikes suggest a
connection problem. Missing ping replies can also mean ICMP is blocked or the
PC is off; ping cannot fully verify the game's UDP connection.

The optional relay copies MaxiTerminal heartbeats only. It helps terminal
discovery but does not carry race traffic or guarantee versus over Wi-Fi.

Detailed instructions: [client setup](client-setup/README.md),
[terminal setup](server-terminal-setup/README.md), and
[player backups](server-tools/README.md). ZIP checksums are in
[SHA256SUMS](releases/SHA256SUMS-v1.7.0.txt).

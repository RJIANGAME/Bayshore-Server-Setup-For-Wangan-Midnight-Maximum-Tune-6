# WMMT6 LAN setup — v1.6.0

For Japanese WMMT6 1.03.04. Use your own game, TeknoParrot installation, and
compatible MaxiTerminal executable. Keep all PCs on the same LAN. Ethernet
provides the most reliable versus connection.

## Server PC: first setup

1. Install [Node.js LTS](https://nodejs.org/en/download) (22 or newer).
2. Download [Server Setup v1.6.0](releases/Bayshore-WMMT6-Server-Setup-v1.6.0.zip?raw=true), extract it to a permanent folder, and keep the whole folder together.
3. Run `Configure-Server.bat` as administrator. Confirm the detected server IPv4 address. It downloads PostgreSQL, creates the database, installs dependencies, and builds Bayshore.
4. Select your compatible `MaxiTerminal.exe`. Optionally enter stable Wi-Fi cabinet IPs separated by commas for the terminal relay, or press Enter to skip. Setup creates configuration and firewall rules for you.
5. Run `server-terminal-setup\Start-Bayshore-And-Terminal.bat` before starting the clients. Share the server IPv4 address with each player.

Allow internet access during first setup. Node.js installation and providing
MaxiTerminal are required; the package supplies the Bayshore server source and
the setup tools. MaxiTerminal and the game are not redistributed.

## Each player PC

1. Download [Client Setup v1.6.0](releases/Bayshore-WMMT6-Client-Setup-v1.6.0.zip?raw=true) and extract a separate copy on each PC. It includes the four verified client assets.
2. Close WMMT6 and TeknoParrot, then run `client-setup\Configure-Client.bat` as administrator.
3. Enter the server IPv4 address, choose a different cabinet number for each PC, and select `wmn6r.exe` and `TeknoParrotUi.exe`.
4. Launch using `WMMT6-Launch.bat` beside `TeknoParrotUi.exe`. It starts AMAuth directly and fits the game into a centered 16:9 borderless window.
5. Check the game's Service menu shows the chosen cabinet number. Esc closes the launcher normally.

Existing users must rerun the new client configurator on every PC. The old
cabinet selector only set AMAuth; v1.6.0 also sets the actual game PCB number.
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
[SHA256SUMS](releases/SHA256SUMS-v1.6.0.txt).

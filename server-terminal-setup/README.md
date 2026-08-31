# Bayshore WMMT6 server terminal setup

This tool configures the WMMT6 1.03.04 terminal service required for cabinets to pass the Wangan Terminal link and serial checks.

1. Extract this folder on the Bayshore server PC.
2. Run `Configure-Server-Terminal.bat` as administrator.
3. Select the configured Bayshore root and your legally obtained `MaxiTerminal.exe` when prompted.
4. Setup verifies the approved SHA-256, copies the executable into the server, generates `config.json` from Bayshore's `serverIp` and `SERVICE_PORT`, and creates the UDP 50765 firewall rule.
5. Use `Start-Bayshore-And-Terminal.bat` for daily startup. It performs a clean restart and starts PostgreSQL, Bayshore, MaxiTerminal, and the recovery watchdog.
6. Use `Stop-Bayshore-And-Terminal.bat` to stop the watchdog, terminal, Bayshore, and bundled PostgreSQL instance.

The watchdog checks the database, Bayshore `/readyz`, MaxiTerminal, and UDP 50765 every 30 seconds. Three failed checks restart the complete stack. It also refreshes the complete stack after 60 minutes without LAN client activity, preventing stale idle services from rejecting the next cabinet. Settings are stored in `server-terminal.json`; set `WatchdogEnabled` to `false` to disable it or change `IdleRestartMinutes` (minimum 5). Recovery history is written to `watchdog.log`.

The ZIP does not contain MaxiTerminal because no redistribution license is available. The approved WMMT6 executable SHA-256 is `DF792DE6500F1A9836439535846B12E2391024E98097DE4E7145F29027F262AF`.

Run only one MaxiTerminal instance per LAN venue. This package is for Japanese WMMT6 revision 1.03.04, not WMMT6R or WMMT6RR.

The terminal is installed on the **server PC**, not in every TeknoParrot client. Its generated `adapter` and `adapter_ip` values use Bayshore's configured server LAN IP. Clients discover it over UDP 50765 on the same LAN.

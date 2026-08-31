# Bayshore WMMT6 server terminal setup

This tool configures the WMMT6 1.03.04 terminal service required for cabinets to pass the Wangan Terminal link and serial checks.

1. Extract this folder on the Bayshore server PC.
2. Run `Configure-Server-Terminal.bat` as administrator.
3. Select the configured Bayshore root and your legally obtained `MaxiTerminal.exe` when prompted.
4. Setup verifies the approved SHA-256, copies the executable into the server, generates `config.json` from Bayshore's `serverIp` and `SERVICE_PORT`, and creates the UDP 50765 firewall rule.
5. Use `Start-Bayshore-And-Terminal.bat` for daily startup. It performs a clean restart and starts PostgreSQL, Bayshore, MaxiTerminal, the optional terminal relay, and the recovery watchdog.
6. Use `Stop-Bayshore-And-Terminal.bat` to stop the watchdog, relay, terminal, Bayshore, and bundled PostgreSQL instance.

The watchdog checks the database, Bayshore `/readyz`, MaxiTerminal, UDP 50765, and the enabled terminal relay every 10 seconds. Three failed checks restart the complete stack. It also refreshes the complete stack after 60 minutes without LAN client activity, preventing stale idle services from rejecting the next cabinet. Settings are stored in `server-terminal.json`; set `WatchdogEnabled` to `false` to disable it or change `IdleRestartMinutes` (minimum 5). Recovery history is written to `watchdog.log`.

## Wi-Fi multicast relay

Some wireless routers pass a cabinet's multicast packets to the server but intermittently drop MaxiTerminal's return multicast packets. When this occurs, the cabinet remains at "Connecting to Wangan Terminal" even though MaxiTerminal is healthy. The optional relay copies only MaxiTerminal heartbeat packets from UDP 50765 to each configured cabinet as ordinary unicast traffic.

Add stable cabinet IPv4 addresses to `server-terminal.json`:

```json
"TerminalRelayEnabled": true,
"TerminalRelayClientIps": ["192.168.0.10", "192.168.0.4"]
```

When automating setup, call `scripts\Configure-Server-Terminal.ps1 -TerminalRelayClientIp <IP1>,<IP2>`; otherwise preserve or edit these generated settings before daily startup. The relay starts and stops with the stack, writes `terminal-relay.log`, and is monitored by the watchdog. Ethernet remains preferable, but the relay provides reliable delivery when the venue must use Wi-Fi.

Daily start does not request administrator elevation. Run `Configure-Server-Terminal.bat` as administrator once to create the firewall rule; the start BAT then keeps any startup error visible in its own window and is safe to run when the database is either running or already stopped. PostgreSQL is launched in a detached hidden process so closing the start BAT window cannot send Ctrl+C to the database and leave every cabinet showing a terminal `NG` result.

The ZIP does not contain MaxiTerminal because no redistribution license is available. The approved WMMT6 executable SHA-256 is `DF792DE6500F1A9836439535846B12E2391024E98097DE4E7145F29027F262AF`.

Run only one MaxiTerminal instance per LAN venue. This package is for Japanese WMMT6 revision 1.03.04, not WMMT6R or WMMT6RR.

The terminal is installed on the **server PC**, not in every TeknoParrot client. Its generated `adapter` and `adapter_ip` values use Bayshore's configured server LAN IP. Clients discover it over UDP 50765 on the same LAN.

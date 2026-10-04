# Bayshore WMMT6 server terminal setup

This tool configures the WMMT6 1.03.04 terminal service required for cabinets to pass the Wangan Terminal link and serial checks.

1. Extract this folder on the Bayshore server PC.
2. Run `Configure-Server-Terminal.bat` as administrator.
3. Select the configured Bayshore root (automatically detected when adjacent) and your legally obtained `MaxiTerminal.exe` when prompted.
4. Enter stable Wi-Fi cabinet IPv4 addresses separated by commas for the optional terminal relay. Enter keeps existing addresses; `NONE` disables it. No JSON editing is needed.
5. Setup verifies the approved SHA-256, backs up existing configuration, copies the executable into the server, generates `config.json` from Bayshore's `serverIp` and `SERVICE_PORT`, and creates scoped UDP 50765 firewall rules for the terminal and enabled relay.
6. Use `Start-Bayshore-And-Terminal.bat` for an interactive clean restart, or the repository-root `Start-Bayshore.cmd` for idempotent automatic startup. Both start PostgreSQL, Bayshore, MaxiTerminal, the optional terminal relay, and the recovery watchdog.
7. Use `Stop-Bayshore-And-Terminal.bat` to stop the watchdog, relay, terminal, Bayshore, and bundled PostgreSQL instance.

The watchdog checks the database, Bayshore `/readyz`, MaxiTerminal, UDP 50765, and the enabled terminal relay every 10 seconds. Three failed checks restart the complete stack. It also refreshes the complete stack after 60 minutes without LAN client activity, preventing stale idle services from rejecting the next cabinet. Settings are stored in `server-terminal.json`; set `WatchdogEnabled` to `false` to disable it or change `IdleRestartMinutes` (minimum 5). Recovery history is written to `watchdog.log`.

## Wi-Fi multicast relay

If versus returns to Story Mode selection, first check that each game Service
menu shows a different cabinet number. Update client setup to v1.7.0 and rerun
it on both PCs. The previous selector changed AMAuth but left the game's PCB
number at 2. The game stores cabinet 1-4 as `mPcbId` 0-3.

Run `Check-Multiplayer-Network.bat` for a read-only loss/latency check. Copy this
server setup folder to a player PC and run the check against the other player's
IP to test that direct path. Failed ICMP replies can also mean an offline PC or
a firewall blocking ping. A stable server connection does not prove the
player-to-player connection is stable. Test with both PCs on Ethernet and the
same LAN; the terminal relay does not relay race traffic.

Some wireless routers pass a cabinet's multicast packets to the server but intermittently drop MaxiTerminal's return multicast packets. When this occurs, the cabinet remains at "Connecting to Wangan Terminal" even though MaxiTerminal is healthy. The optional relay copies only MaxiTerminal heartbeat packets from UDP 50765 to each configured cabinet as ordinary unicast traffic.

Add stable cabinet IPv4 addresses to `server-terminal.json`:

```json
"TerminalRelayEnabled": true,
"TerminalRelayClientIps": ["192.168.0.10", "192.168.0.4"]
```

The interactive installer now asks for these addresses. When automating setup, call `scripts\Configure-Server-Terminal.ps1 -TerminalRelayClientIp <IP1>,<IP2>` or use `-NonInteractive` to preserve existing relay addresses without a prompt. The relay starts and stops with the stack, writes `terminal-relay.log`, and is monitored by the watchdog. Ethernet remains preferable; terminal heartbeats over unicast do not guarantee a stable versus connection.

Daily start requests administrator elevation only when Windows IIS owns TCP 80. In that case it stops IIS, changes its startup type to Manual, and continues automatically after the normal UAC approval. Run `Configure-Server-Terminal.bat` as administrator once to create the firewall rule. The repository-root `Start-Bayshore.cmd` is safe for automatic startup and does not restart an already healthy stack. PostgreSQL is launched in a detached hidden process so closing a launcher window cannot send Ctrl+C to the database and leave every cabinet showing a terminal `NG` result.

The ZIP does not contain MaxiTerminal because no redistribution license is available. The approved WMMT6 executable SHA-256 is `DF792DE6500F1A9836439535846B12E2391024E98097DE4E7145F29027F262AF`.

Run only one MaxiTerminal instance per LAN venue. This package is for Japanese WMMT6 revision 1.03.04, not WMMT6R or WMMT6RR.

The terminal is installed on the **server PC**, not in every TeknoParrot client. Its generated `adapter` and `adapter_ip` values use Bayshore's configured server LAN IP. Clients discover it over UDP 50765 on the same LAN.

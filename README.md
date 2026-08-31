<div align="center">

# BAYSHORE + WMMT6 Universal Self-Hosting Guide

**From-Zero Build · Client Integration · Operations · Troubleshooting · Cautions**

</div>

| Guide metadata | Value |
|---|---|
| **Scope** | Japanese Wangan Midnight Maximum Tune 6 (WMMT6) |
| **Audience** | Windows users building a private LAN server from their own files |
| **Edition** | Universal, 2026-08-29 |

> [!IMPORTANT]
> This guide is for **WMMT6 only**. It is **not** a WMMT6R or WMMT6RR guide. Those releases use different profiles, software revisions, terminal packages, patches, and server implementations.

> [!CAUTION]
> Use only a clean Japanese WMMT6 game dump that you are legally entitled to possess. This guide does not provide or authorize distribution of copyrighted game data.

## Universal Client Configurator

The repository now includes a [client-only configurator](client-setup) for a new cabinet that already has TeknoParrot and a legally obtained Japanese WMMT6 1.03.04 installation. The client does not need the full Bayshore source tree, Node.js, or PostgreSQL.

Run `client-setup\Configure-Client.bat` as administrator. Setup will:

1. ask the user to type the Bayshore server IPv4 address;
2. validate the address and ask for a unique drive cabinet number from 1 through 4;
3. ask the user to select `wmn6r.exe` and `TeknoParrotUi.exe` instead of locating them automatically;
4. auto-detect the active client adapter and router;
5. back up and configure AMAuth launching, hosts, certificates, OpenParrot/OpenBanapass, multicast routing, firewall rules, unique card/cabinet identities, and the existing WMMT6 user profile;
6. install `WMMT6-Borderless.bat` plus its helper and generated launcher configuration directly in the selected TeknoParrot root.

The public release does not redistribute the game or MaxiTerminal. It includes four verified Bayshore-specific assets and deliberately preserves TeknoParrot's installed `OpenParrot64.dll`. The configurator performs a complete read-only preflight before changing anything and never automatically selects a WMMT6 ROM.

After configuration, run `WMMT6-Borderless.bat` beside `TeknoParrotUi.exe`. It starts AMAuth outside OpenParrot injection and launches the existing WMMT6 profile in centered, monitor-aware 16:9 borderless mode. Setup removes obsolete `WMMT6-Bayshore.xml` copies, so TeknoParrot no longer shows a second `Metadata Missing` game.

For multicast, setup creates `225.0.0.1/32` as an on-link route (`0.0.0.0` next hop). It uses `New-NetRoute` with its default active-and-persistent behavior and falls back to persistent `netsh` or `route.exe` syntax when necessary.

The client preflight also checks administrator rights and the x64 Visual C++ 2010 SP1 runtime required by `iauthdll.dll`. Registration runs from the AMCUS directory; an existing COM registration is accepted only if its DLL hash matches the selected client DLL.

Client setup v1.1.8 fixes OpenParrot detection for the supported WMMT6 1.03.04 executable (CRC `7E804704`) and removes the extra Maxitune debug console from release builds.

Client setup v1.1.9 leaves both WMMT6 executables under TeknoParrot's control. The borderless helper no longer starts or stops a second `AMAuthd.exe`, preventing duplicate OpenParrot injection and access-violation crashes on two-executable profiles.

Client setup v1.2.0 supersedes v1.1.9 after crash evidence showed that TeknoParrot injected `OpenParrot64.dll` into `AMAuthd.exe`. It generates `WMMT6-Bayshore.xml` profile copies with the second executable disabled, starts AMAuth directly, and uses OpenParrot only for `wmn6r.exe`. Existing profiles remain unchanged.

Client setup v1.3.0 removes the custom OpenParrot DLL after repeated `0xc0000005` crashes inside its native WMMT6/D3D hooks. Setup now preserves the TeknoParrot-supplied DLL and rejects the known crashing hashes from earlier releases.

Client setup v1.4.0 supports up to four simultaneous LAN cabinets by assigning a unique AMAuth `netID` to each client. It also detects the WMMT6 drive serial embedded in OpenParrot and writes the exact matching `serialID`, preventing startup from stopping between ALL.Net and MUCHA.

Client setup v1.4.1 corrects E0517 by using OpenParrot's `280811...` AMAuth identity for `WritableConfig.ini`, not its separate `280813...` drive-dongle identity.

Client setup v1.3.1 configures the existing WMMT6 user profile directly, applies the selected game path, keeps `Windowed=0` to avoid the confirmed OpenParrot DXGI crash, applies the detected client adapter and real default gateway, removes obsolete duplicate profiles, and reinforces borderless styling while the game runs.

## Server MaxiTerminal Setup

WMMT6 cabinets cannot pass the terminal link checks with Bayshore alone. Install one venue MaxiTerminal on the server PC using [`server-terminal-setup`](server-terminal-setup):

1. Run `Configure-Server-Terminal.bat` as administrator.
2. Select the configured Bayshore root.
3. Select your legally obtained `MaxiTerminal.exe`.
4. Use `Start-Bayshore-And-Terminal.bat` for daily startup. It cleanly restarts PostgreSQL, Bayshore, and MaxiTerminal, then runs a recovery watchdog.

The installer verifies the approved WMMT6 binary, copies it into `bin\MaxiTerminal`, generates its configuration from Bayshore's `serverIp` and `SERVICE_PORT`, and opens inbound UDP 50765. The public ZIP cannot include MaxiTerminal itself because no redistribution license is available.

The watchdog checks the complete stack every 30 seconds and restarts it after three consecutive health failures. It also restarts after 60 minutes without LAN client activity so a stale idle terminal/database session cannot block the next cabinet. `Stop-Bayshore-And-Terminal.bat` stops PostgreSQL as well as Bayshore, MaxiTerminal, and the watchdog. See [`server-terminal-setup/README.md`](server-terminal-setup/README.md) for settings and logs.

## Player Data Backup, Restore, and Merge

The repository includes root-level database tools for the portable Bayshore server:

| Tool | Result |
|---|---|
| `Backup-Player-Data.bat` | Creates `backups\bayshore-YYYYMMDD-HHMMSS.dump` under the Bayshore server root. |
| `Restore-Player-Data.bat` | Preserves MaxiTerminal configuration, replaces the current save atomically, then restarts the configured combined stack. |
| `Merge-Player-Data.bat` | Preserves MaxiTerminal configuration, imports previously unseen card IDs, then restarts the configured combined stack. |

Keep the BAT files and `server-tools` folder together in the Bayshore server root. Restore requires typing `RESTORE`; merge requires typing `MERGE`. Both operations stop the Bayshore application while PostgreSQL is changed, preserve `bin\MaxiTerminal\config.json` as a timestamped backup, restore the exact file afterward, and restart Bayshore plus MaxiTerminal when the combined launcher is installed.

The conservative merge imports core player/card progress and remaps database IDs. Duplicate cards and destination-wide crowns, events, rankings, rival history, and place/file records remain unchanged. Both databases must use the same Bayshore migration set. See [`server-tools/README.md`](server-tools/README.md) for the exact scope and recovery procedure.

## Graphical Database Editor

`Bayshore-Database-Editor.bat` opens a dependency-free Python/Tkinter table browser for the portable PostgreSQL database. It reads the existing `.env`, uses the bundled PostgreSQL tools, supports paginated browsing, search, primary-key-targeted cell edits, inserts, deletes, and an advanced SQL console.

Safety backups are enabled by default before every write and are stored under `backups` with a `before-db-editor-` prefix. Stop Bayshore and MaxiTerminal before changing player data, but leave PostgreSQL running so the editor can connect. See [`database-editor/README.md`](database-editor/README.md).

## Quick Architecture

```text
PostgreSQL
    ↑
    │
Bayshore  ←────  MaxiTerminal
    ↑
    │
AMAuth/MUCHA  ←────  WMMT6 drive cabinet
                     via OpenParrot/OpenBanapass
```

A one-PC deployment still requires a stable IPv4 address on the physical LAN adapter because WMMT6 does not behave like an ordinary localhost-only application.

---

## Table of Contents

- [Universal Client Configurator](#universal-client-configurator)
- [Graphical Database Editor](#graphical-database-editor)
- [1. INSTALLATION WORKSHEET](#1-installation-worksheet)
- [2. COMPATIBILITY AND KNOWN-GOOD TARGET](#2-compatibility-and-known-good-target)
- [3. ARCHITECTURE AND PORT MAP](#3-architecture-and-port-map)
- [4. SECURITY, TRUST, AND LEGAL CAUTIONS](#4-security-trust-and-legal-cautions)
- [5. REQUIRED SOFTWARE](#5-required-software)
- [6. PREPARE THE NETWORK](#6-prepare-the-network)
- [7. OBTAIN AND PREPARE BAYSHORE](#7-obtain-and-prepare-bayshore)
- [8. BUILD PROJECT ASAKURA OPENPARROT](#8-build-project-asakura-openparrot)
- [9. BUILD AND INSTALL OPENBANAPASS](#9-build-and-install-openbanapass)
- [10. CONFIGURE AMAUTH AND MUCHA](#10-configure-amauth-and-mucha)
- [11. INSTALL BAYSHORE CERTIFICATE FILES](#11-install-bayshore-certificate-files)
- [12. INSTALL AND CONFIGURE MAXITERMINAL](#12-install-and-configure-maxiterminal)
- [13. CONFIGURE TEKNOPARROT](#13-configure-teknoparrot)
- [14. CUSTOMIZE THE INCLUDED ONE-CLICK LAUNCHER](#14-customize-the-included-one-click-launcher)
- [15. CORRECT STARTUP ORDER](#15-correct-startup-order)
- [16. SUCCESS VALIDATION](#16-success-validation)
- [17. TROUBLESHOOTING](#17-troubleshooting)
- [18. WRONG THINGS TO AVOID](#18-wrong-things-to-avoid)
- [19. SHUTDOWN, BACKUP, AND RESTORE PREPARATION](#19-shutdown-backup-and-restore-preparation)
- [20. PORTABLE CHECKLIST FOR A NEW COMPUTER](#20-portable-checklist-for-a-new-computer)
- [21. EXAMPLE WORKSHEET (EXAMPLE ONLY)](#21-example-worksheet-example-only)
- [22. REFERENCES](#22-references)
- [References](#22-references)

---

## Read This First

This guide deliberately uses placeholders instead of one person's drive letters, usernames, adapter names, or IP addresses. Complete the worksheet in **Section 1** before changing any files.

This guide is for **WMMT6**. It is not a WMMT6R or WMMT6RR guide. Those releases use different profiles, software revisions, terminal packages, patches, and server implementations. Mixing them is a common reason for endless startup checks, offline status, and failed cards.

You must provide a clean Japanese WMMT6 game dump that you are legally entitled to possess. This guide does not provide or authorize distribution of copyrighted game data.

The word **"server"** can mean three different things in this setup:

1. **Bayshore** — the Node.js WMMT6 backend.
2. **AMAuth/MUCHA** — the game's authentication layer.
3. **MaxiTerminal** — the Wangan Terminal emulator used by the cabinet.

All three must be available before the drive cabinet can finish booting.

## 1. INSTALLATION WORKSHEET

Choose and record these values before starting. Substitute them everywhere this guide shows angle brackets.

| Placeholder | Meaning / recommended value |
|---|---|
| `<BAYSHORE_DIR>` | Absolute folder containing package.json and the scripts folder. Example: D:\Arcade\Bayshore |
| `<TEKNOPARROT_DIR>` | Absolute folder containing TeknoParrotUi.exe. Example: D:\Arcade\TeknoParrot |
| `<WMMT6_DIR>` | Absolute folder containing wmn6r.exe. Example: D:\Arcade\Games\WMMT6 |
| `<AMCUS_DIR>` | Normally <WMMT6_DIR>\AMCUS |
| `<MAXITERMINAL_DIR>` | Folder containing MaxiTerminal.exe and config.json. Recommended: <BAYSHORE_DIR>\bin\MaxiTerminal |
| `<LAN_IP>` | Stable IPv4 address of the Windows computer running the cabinet/server. Example: 192.168.1.50 |
| `<ROUTER_IP>` | Default gateway on the same LAN. Example: 192.168.1.1 |
| `<PREFIX_LENGTH>` | Usually 24, equal to subnet mask 255.255.255.0. |
| `<LAN_ADAPTER>` | Physical Ethernet/Wi-Fi adapter that owns <LAN_IP>. Example: Ethernet or TP-Link |
| `<DB_USER>` | Recommended: bayshore |
| `<DB_NAME>` | Recommended: bayshore |
| `<DB_PASSWORD>` | A long, random, URL-safe password. Never use a guide's example password. |
| `<DB_PORT>` | Normally 5432 |
| `<ALLNET_PORT>` | Normally 80 |
| `<MUCHA_PORT>` | Normally 10082 |
| `<SERVICE_PORT>` | Normally 9002 |

**Commands that help identify the correct LAN address:**

```powershell
ipconfig
Get-NetIPConfiguration
```

Choose the address on the adapter that reaches your router. **Do not choose:**

- `127.0.0.1`
- a `169.254.x.x` self-assigned address
- a disconnected adapter
- VirtualBox/VMware host-only Ethernet
- a VPN adapter
- Bluetooth networking

## 2. COMPATIBILITY AND KNOWN-GOOD TARGET

**Target client:**

| Parameter | Known-good target |
|---|---|

**Server:**

- Project Asakura Bayshore
- <https://github.com/ProjectAsakura/Bayshore>

**Client projects:**

- Project Asakura OpenParrot fork
- Project Asakura OpenBanapass
- A WMMT6-compatible MaxiTerminal distribution

> [!CAUTION]
> Do not continue if the game screen says **WMMT6R** or **WMMT6RR**. Obtain the guide and components made for that exact release instead.

## 3. ARCHITECTURE AND PORT MAP

### Startup / data flow

```text
PostgreSQL
    ↑
    │
Bayshore  ←────  MaxiTerminal
    ↑
    │
AMAuth/MUCHA  ←────  WMMT6 drive cabinet via OpenParrot/OpenBanapass
```

### Default ports

| Protocol | Port | Purpose |
|---|---:|---|
| TCP | `80` | ALL.Net startup |
| TCP | `10082` | MUCHA authentication |
| TCP | `9002` | WMMT6 HTTPS game service and health endpoint |
| TCP | `5432` | PostgreSQL — keep on loopback only |
| TCP | `12345` | Local AMAuth-to-MUCHA connection |
| UDP | `50765` | WMMT6 cabinet/terminal multicast traffic |

**Multicast group:** `225.0.0.1`

For a one-PC setup, WMMT6, MaxiTerminal, AMAuth, Bayshore, and PostgreSQL all run on the same Windows computer. A stable physical-LAN IPv4 address is still required because WMMT6 does not behave like an ordinary localhost program.

## 4. SECURITY, TRUST, AND LEGAL CAUTIONS

> [!WARNING]
> Read this section before running third-party binaries, exposing services, editing certificates, or changing firewall rules.

1. Use only game files you legally possess. Never include the game dump in a server archive or public repository.
2. MaxiTerminal is community software and may be unsigned. Obtain it from a source you trust, record its SHA-256 hash, and keep the original archive. Do not run a random binary simply because its filename says MaxiTerminal.
3. OpenParrot and OpenBanapass are game hooks. Build from the identified source revisions when possible and keep hashes of working binaries.
4. Bayshore uses a self-signed certificate and the game normally uses sslverify=0. Keep the system on a trusted LAN. For remote users, use a VPN. Do not directly port-forward this legacy stack to the public internet.
5. PostgreSQL must listen on 127.0.0.1 for a one-PC deployment. Never expose TCP 5432 to the internet.
6. .env contains a database password. Never commit it, upload it, paste it into chat, or show it in screenshots.
7. server_wangan.key is a private TLS key. Do not publish it.
8. Do not disable antivirus or Windows Firewall globally. If a verified file needs an exception, scope it to that exact file/folder and required ports.
9. AMAuthd builds may alter the Windows clock/timezone. Check the clock after first launch. Never apply a hex patch made for a different AMAuthd binary.
10. Back up the game, database, configurations, and known-working DLLs before updating anything.

## 5. REQUIRED SOFTWARE

**Install:**

- 64-bit Windows 10 or Windows 11
- Git for Windows
- Node.js 20 or newer; Node.js 22 LTS recommended for this deployment
- npm (included with Node.js)
- Visual Studio 2022 or newer
- Desktop development with C++ workload
- MSVC x64/x86 build tools
- Windows 10/11 SDK
- .NET desktop workload if building a custom TeknoParrotUI
- Microsoft Visual C++ redistributables required by the game
- TeknoParrot with the WMMT6 profile

**Verify:**

```text
node --version
npm --version
git --version
```

This deployment's Setup.ps1 enforces Node.js 20+. Older community guides may say Node.js 16; that advice applies to an older dependency set, not this one.

**Visual Studio v143 error:**

If the solution requests Platform Toolset v143, modify the Visual Studio installation and add MSVC v143 plus a Windows SDK. Alternatively, generate the solution using the repository's premake step and retarget it to an installed compatible toolset. Always compile WMMT6 client components as Release x64.

## 6. PREPARE THE NETWORK

Give `<LAN_ADAPTER>` a stable address using a router DHCP reservation or a carefully configured static IPv4 address.

**Example only:**

| Setting | Example |
|---|---|
| IP | `192.168.1.50` |
| Prefix length | `24` |
| Gateway | `192.168.1.1` |

**Confirm:**

```powershell
ping <ROUTER_IP>
Get-NetIPAddress -AddressFamily IPv4 -IPAddress <LAN_IP>
```

WMMT6 terminal multicast must use the same physical adapter. A persistent host route is recommended:

```text
Destination: 225.0.0.1/32
Interface:   the interface that owns <LAN_IP>
```

The included scripts\Set-WMMT6Route.ps1 was originally configured for a specific IP. Before using it on another computer, replace its hard-coded adapter address with <LAN_IP>, or parameterize it.

**After launch, verify:**

```powershell
route print 225.0.0.1
netsh interface ipv4 show joins
```

`225.0.0.1` must appear under `<LAN_ADAPTER>`, not under a VM/VPN adapter.

## 7. OBTAIN AND PREPARE BAYSHORE

### 7.1 Clone

```powershell
git clone https://github.com/ProjectAsakura/Bayshore.git <BAYSHORE_DIR>
cd /d <BAYSHORE_DIR>
```

If using a prepared deployment package containing scripts\Setup.ps1, scripts\Start-WMMT6.ps1, and Start-WMMT6.cmd, extract it to <BAYSHORE_DIR> without nesting another Bayshore folder inside it.

### 7.2 Automated setup (recommended for this deployment package)

**Open PowerShell in <BAYSHORE_DIR>:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Setup.ps1 -ServerIp <LAN_IP>
```

**The setup should:**

- verify Node.js 20+;
- generate a random database password in .env;
- create config.json;
- run npm ci;
- generate the Prisma client;
- install/initialize portable PostgreSQL by default;
- deploy migrations;
- build protobuf definitions and TypeScript.

> [!CAUTION]
> Do not interrupt PostgreSQL initialization or npm installation.

### 7.3 Manual setup when Setup.ps1 is unavailable

1. Copy .env.example to .env.
2. Copy config.example.json to config.json.
3. Generate a long random URL-safe database password.
4. Install/create PostgreSQL and the selected database/user.
5. Edit .env and config.json as described below.
6. Run:

```text
npm ci
npm run prisma-generate
npm run db:migrate
npm run build
```

### 7.4 .env template

```dotenv
POSTGRES_URL=postgresql://<DB_USER>:<DB_PASSWORD>@127.0.0.1:<DB_PORT>/<DB_NAME>
POSTGRES_PASSWORD=<DB_PASSWORD>
POSTGRES_PORT=<DB_PORT>
ALLNET_PORT=<ALLNET_PORT>
MUCHA_PORT=<MUCHA_PORT>
SERVICE_PORT=<SERVICE_PORT>
OPENTELEMETRY_ENABLED=false
OPENTELEMETRY_OTLP_URI=disregard-this
```

**Rules:**

- POSTGRES_PASSWORD must match the password inside POSTGRES_URL.
- Use a URL-safe password or correctly percent-encode it.
- Do not add quotes unless the application's parser expects them.
- Keep .env out of source control.

### 7.5 config.json essentials

```text
"serverIp": "<LAN_IP>"
```

**Recommended initial game options:**

```text
"newCardsBanned": 0
"revisionCheck": 1
"scratchEnabled": 1
```

Choose a unique placeId/shop name for your private server. Do not copy a public server's identity.

### 7.6 Start and verify Bayshore alone

**From <BAYSHORE_DIR>:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start.ps1 -Background
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\HealthCheck.ps1
```

**Expected health result:**

```json
{"status":"ready","database":"ok"}
```

**Expected listeners:**

- ALL.Net on `<ALLNET_PORT>`
- MUCHA on `<MUCHA_PORT>`
- Game service on `<SERVICE_PORT>`

**Logs:**

```text
<BAYSHORE_DIR>\.data\bayshore.out.log
<BAYSHORE_DIR>\.data\bayshore.err.log
<BAYSHORE_DIR>\.data\postgres.log
```

## 8. BUILD PROJECT ASAKURA OPENPARROT

Use the Project Asakura OpenParrot fork required by the Bayshore client workflow. Do not silently substitute a current generic OpenParrot build.

**General build procedure:**

1. Clone the Asakura OpenParrot source.
2. Run its premake/generation script.
3. Open OpenParrot.sln.
4. Select Release and x64.
5. Build the solution.

**Expected files include:**

```text
OpenParrot64.dll
OpenParrotLoader64.exe
```

**Copy/install the x64 core to:**

```text
<TEKNOPARROT_DIR>\OpenParrotx64\OpenParrot64.dll
```

Keep a backup and SHA-256 hash of the known-working file.

**Multicast caution:**

> [!CAUTION]
> On Windows with VM/VPN adapters, WMMT6 can join `225.0.0.1` on the wrong interface. The prepared OpenParrot source includes a WMMT6 correction that forces multicast membership onto `NetworkAdapterIP`. If building from plain upstream source, verify whether that correction exists before assuming the Windows route alone is sufficient.

> [!CAUTION]
> Do not let a later TeknoParrot update silently overwrite the tested custom OpenParrot64.dll.

## 9. BUILD AND INSTALL OPENBANAPASS

Clone Project Asakura OpenBanapass, open its solution, select Release x64, and build it.

**Copy the generated bngrw.dll to:**

```text
<WMMT6_DIR>\bngrw.dll
```

It must sit beside wmn6r.exe. A 32-bit DLL will not work with the x64 game.

**In WMMT6.xml set:**

```text
Banapass Connection = 1
```

At the in-game Banapassport prompt, focus the game and hold C for about one second. A very quick tap can be missed.

## 10. CONFIGURE AMAUTH AND MUCHA

**Verify <AMCUS_DIR> contains at least:**

```text
AMAuthd.exe
iauthdll.dll
AMConfig.ini
MuchaBin\muchacd.exe (or the dump's equivalent)
```

An incomplete AMCUS folder means the game dump is unsuitable for this setup.

Register `iauthdll.dll` from an elevated command prompt, or let the included launcher do it:

```powershell
cd /d <AMCUS_DIR>
regsvr32 iauthdll.dll
```

**Edit AMConfig.ini while preserving Shift-JIS encoding:**

```ini
cacfg-auth_server_url=https://<LAN_IP>:<MUCHA_PORT>/
cacfg-auth_server_sslverify=0
amdcfg-writableConfig=<AMCUS_DIR>\WritableConfig.ini
dtcfg-dl_image_path=<AMCUS_DIR>\dl_image
```

**Create <AMCUS_DIR>\WritableConfig.ini:**

```ini
[RuntimeConfig]
mode=
netID=1
serialID=280811990002
```

`netID` is the drive cabinet number, not the card ID. Use a different value from `1` through `4` on every simultaneously active cabinet. For example, the second computer must use `netID=2`; duplicate `netID=1` clients conflict even when their card IDs and `serialID` values differ. `serialID` must use the AMAuth identity embedded in OpenParrot (`280811990002` in the identified source). Do not use its separate `280813...` drive-dongle identity in `WritableConfig.ini`. If a custom OpenParrot build changes the AMAuth identity, the configuration must use the same full 12 digits. Do not casually rewrite serial bytes inside captured packets; integrity fields may depend on the content.

> [!CAUTION]
> Do not save AMConfig.ini as UTF-8. Do not start AMAuthd twice.

## 11. INSTALL BAYSHORE CERTIFICATE FILES

Back up the original game certificate directories first.

**Copy <BAYSHORE_DIR>\server_wangan.crt to:**

```text
<WMMT6_DIR>\data_jp\network\certs\terminal-cert_v388.pem
<WMMT6_DIR>\data_jp\network\certs\v388-ca-cert.pem
```

**Copy <BAYSHORE_DIR>\server_wangan.key to:**

```text
<WMMT6_DIR>\data_jp\network\private\terminal-key_v388.pem
```

Verify SHA-256 hashes: both certificate destinations must match the source certificate, and the private destination must match the source private key.

> [!WARNING]
> Never combine a certificate from one checkout with a private key from another. Never publish server_wangan.key.

## 12. INSTALL AND CONFIGURE MAXITERMINAL

Use a MaxiTerminal build intended for WMMT6 1.03.04. Keep MaxiTerminal.exe and config.json together in <MAXITERMINAL_DIR>.

**Before running an unsigned binary:**

```powershell
Get-FileHash -Algorithm SHA256 <MAXITERMINAL_DIR>\MaxiTerminal.exe
Get-AuthenticodeSignature <MAXITERMINAL_DIR>\MaxiTerminal.exe
```

Record the result in your installation notes.

**Set these config.json fields:**

```text
"adapter": "<LAN_IP>"
"adapter_ip": "<LAN_IP>"
"online_mode": "1"
"server_uri": "https://<LAN_IP>:<SERVICE_PORT>"
"software_revision": "10304"
"event_mode": "0"
"freeplay": "0" or the intended cabinet pricing mode
"feature_year": "2018"
```

> [!CAUTION]
> Do not leave adapter/adapter_ip at 0.0.0.0 on a computer with several network interfaces. Do not run a WMMT6R/6RR terminal with WMMT6.

**After launch, expected UDP ownership is conceptually:**

```text
0.0.0.0:50765       wmn6r.exe
<LAN_IP>:50765       MaxiTerminal.exe
```

**Check with:**

```powershell
netstat -ano -p udp | findstr 50765
```

MaxiTerminal is not equivalent to a simple static six-packet sender. A static sender may place traffic on the wire yet still fail the terminal protocol and leave the cabinet showing terminal link NG.

## 13. CONFIGURE TEKNOPARROT

Add Wangan Midnight Maximum Tune 6, then save its profile as WMMT6.xml.

**Required profile values:**

```text
GamePath:             <WMMT6_DIR>\wmn6r.exe
TerminalMode:         0
Banapass Connection:  1
NetworkAdapterIP:     <LAN_IP>
RouterIP:             <ROUTER_IP>
TerminalEmulator:     1
Windowed:             0
WhiteScreenFix:       0
```

The universal configurator backs up and edits the existing WMMT6 user profile. It does not generate a second GameProfile. The profile uses these values because the borderless launcher starts AMAuth directly, outside OpenParrot injection:

```text
HasTwoExecutables = false
LaunchSecondExecutableFirst = false
```

Use `WMMT6.xml`. Never use `WMMT6R.xml` or `WMMT6RR.xml` for this client.

Keep `Windowed=0`. The confirmed OpenParrot 1.0.0.784 windowed DXGI path can crash this supported game executable. `WMMT6-Borderless.bat` handles borderless fullscreen externally and keeps removing any title bar recreated during startup.

`TerminalMode` must remain `0` on the drive cabinet. `TerminalMode 1` is used only when another full WMMT6 instance acts as a terminal on a separate computer.

## 14. CUSTOMIZE THE INCLUDED ONE-CLICK LAUNCHER

**The prepared deployment includes:**

```text
<BAYSHORE_DIR>\Start-WMMT6.cmd
<BAYSHORE_DIR>\scripts\Start-WMMT6.ps1
<BAYSHORE_DIR>\scripts\Set-WMMT6Route.ps1
```

Before another person uses these scripts, open `Start-WMMT6.ps1` and replace all installation-specific defaults:

```text
TeknoParrot root      -> <TEKNOPARROT_DIR>
profile path          -> <TEKNOPARROT_DIR>\UserProfiles\WMMT6.xml
game root             -> <WMMT6_DIR>
terminal root         -> <MAXITERMINAL_DIR>
custom OpenParrot DLL -> actual Release x64 build output
adapter address       -> <LAN_IP>
```

Open Set-WMMT6Route.ps1 and replace its hard-coded adapter IP with <LAN_IP>.

Open <MAXITERMINAL_DIR>\config.json and confirm its two adapter fields and server_uri match the same <LAN_IP>.

**Search for old machine-specific values before launch. From <BAYSHORE_DIR>:**

```powershell
rg -n "192\.168\.|F:\\|C:\\Users\\" scripts bin\MaxiTerminal config.json
```

Review every result. Do not perform a blind global replacement inside binary files or the game dump.

## 15. CORRECT STARTUP ORDER

> [!IMPORTANT]
> Startup order matters. Do not manually launch duplicate components while the one-click launcher is running.

**Recommended one-click procedure:**

1. Confirm <LAN_ADAPTER> is connected and owns <LAN_IP>.
2. Double-click <BAYSHORE_DIR>\Start-WMMT6.cmd.
3. Approve the Windows UAC prompt.
4. Wait; do not manually launch duplicate components.
5. Allow startup checks to complete.
6. At the Banapassport prompt, focus WMMT6 and hold C for one second.

**The correct internal order is:**

1. Stop stale WMMT6, TeknoParrot, terminal, AMAuth, and MUCHA processes.
2. Install/verify the custom OpenParrot64.dll.
3. Register iauthdll.dll.
4. Start PostgreSQL.
5. Migrate/build/start Bayshore.
6. Wait for /readyz to report ready/database ok.
7. Install/verify the 225.0.0.1 route.
8. Start MaxiTerminal.
9. Start AMAuthd and wait for MUCHA on local TCP 12345.
10. Launch the TeknoParrot WMMT6 profile.

**Do not:**

- double-click wmn6r.exe directly;
- run the game dump's original init.ps1;
- start TeknoParrot before the services;
- start WMMT6Terminal.exe alongside MaxiTerminal;
- cancel UAC and assume a newly built DLL was installed.

## 16. SUCCESS VALIDATION

### 16.1 Health endpoint

**From <BAYSHORE_DIR>:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\HealthCheck.ps1
```

**Expected:**

{"status":"ready","database":"ok"}

### 16.2 Server log

**Expected startup lines:**

ALL.net server listening on port <ALLNET_PORT> Mucha server listening on port <MUCHA_PORT> Game server listening on port <SERVICE_PORT>

**Expected client/terminal requests include:**

```text
POST /sys/servlet/PowerOn
POST /wmmt6/method/register_system_info
GET  /wmmt6/resource/place_list
GET  /wmmt6/resource/file_list
POST /wmmt6/method/register_system_stats
```

The /wmmt6/ resource calls and register_system_stats are stronger evidence than seeing only a PowerOn request.

### 16.3 Processes and sockets

**Exactly one of each should normally run:**

```text
node.exe (Bayshore)
postgres.exe processes belonging to the selected instance
MaxiTerminal.exe
AMAuthd.exe
muchacd.exe
TeknoParrotUi.exe
OpenParrotLoader64.exe
wmn6r.exe
```

**Check listeners:**

```powershell
netstat -ano | findstr ":80 :10082 :9002 :12345 :50765 :5432"
```

Identify a PID before stopping it. Never kill a process solely because its PID resembles an example from another computer.

### 16.4 Japanese startup terms

| Display | Meaning |
|---|---|
| `OK` | passed |
| `NG` | failed |
| `チェック中...` | checking |
| `オフライン` | offline |
| `湾岸ターミナルリンク状況` | Wangan Terminal link status |
| `ゲームサーバー接続チェック` | game server connection check |

> [!IMPORTANT]
> A red NG is a failure, not a slow-loading indication. Waiting indefinitely will not repair an NG result.

## 17. TROUBLESHOOTING

### A. Terminal link is NG / terminal serial keeps checking

- Confirm the real MaxiTerminal is running.
- Confirm adapter and adapter_ip equal <LAN_IP>.
- Confirm server_uri points to https://<LAN_IP>:<SERVICE_PORT>.
- Confirm both wmn6r and MaxiTerminal own UDP 50765 sockets.
- Confirm 225.0.0.1 joined <LAN_ADAPTER>.
- Disable/exit a VPN temporarily if it steals multicast routing.
- Check Windows Firewall rules for these exact verified executables.
- Do not run a second terminal emulator.
- Do not substitute a WMMT6R/6RR MaxiTerminal package.

### B. Game server says offline

- Run HealthCheck.ps1.
- Check TCP <ALLNET_PORT>, <MUCHA_PORT>, and <SERVICE_PORT> listeners.
- Check AMConfig.ini auth URL and sslverify.
- Restart AMAuthd and muchacd as a matched pair using the launcher.
- Look for a new /sys/servlet/PowerOn in bayshore.out.log.
- Check system date/time.

### C. Startup remains on checking for several minutes

- Read the exact last red/checking row; do not merely wait longer.
- Inspect bayshore.out.log and bayshore.err.log.
- Check terminal and AMAuth processes did not exit.
- Check port ownership and adapter membership.
- Restart using the full launcher, not only wmn6r.exe.

### D. iauthdll registration error

- Confirm iauthdll.dll exists in <AMCUS_DIR>.
- Use an Administrator prompt.
- Confirm the AMCUS directory is complete.
- Install required Microsoft Visual C++ runtimes.
- Do not borrow iauthdll.dll from a different game/revision.

### E. Banapassport does not scan

- Confirm x64 bngrw.dll is beside wmn6r.exe.
- Confirm Banapass Connection=1.
- Focus the game and hold C for one second.
- Check for conflicting C-key bindings.
- Confirm the game reached the actual card prompt rather than guest mode.

### F. Database is unavailable

- Read .data\postgres.log.
- Confirm the database password matches in both .env fields.
- Run npm run db:status.
- Start the selected PostgreSQL instance.
- Do not delete the database as the first troubleshooting action.

### G. Port already in use

- Run netstat and identify the owner.
- Stop only the stale WMMT6/Bayshore component.
- Do not change standard ports randomly; every dependent config must match.

### H. Newly built OpenParrot appears to have no effect

- Close the elevated game/loader first; Windows locks the loaded DLL.
- Approve UAC when the launcher replaces it.
- Compare SHA-256 of build output and installed DLL.
- Confirm TeknoParrot points to the intended OpenParrot loader/core.

## 18. WRONG THINGS TO AVOID

> [!WARNING]
> Treat this section as a pre-launch safety checklist. Avoid these mistakes before troubleshooting individual components.

- Mixing WMMT6, WMMT6R, and WMMT6RR components.
- Treating terminal link NG as ordinary loading.
- Replacing MaxiTerminal with a static packet spammer.
- Running two terminal emulators or two AMAuth instances.
- Reusing stale AMAuth/MUCHA after repeatedly restarting only the game.
- Starting the game before Bayshore and MaxiTerminal are ready.
- Selecting a VM/VPN adapter for NetworkAdapterIP.
- Leaving MaxiTerminal adapter fields at 0.0.0.0 on a multi-adapter PC.
- Saving AMConfig.ini as UTF-8 instead of Shift-JIS.
- Using a 32-bit OpenBanapass DLL.
- Allowing TeknoParrot updates to replace the custom Asakura core unnoticed.
- Copying an entire old TeknoParrot bundle over a current installation.
- Editing captured terminal serials without recalculating integrity data.
- Canceling UAC, then testing the still-loaded old DLL.
- Exposing PostgreSQL or sslverify=0 services publicly.
- Committing .env or server_wangan.key.
- Deleting database files to fix a network/client problem.
- Applying undocumented binary patches to a different game revision.
- Changing many variables at once without backups and hashes.
- Distributing copyrighted game files.

## 19. SHUTDOWN, BACKUP, AND RESTORE PREPARATION

Close WMMT6 normally when possible.

**Stop Bayshore:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <BAYSHORE_DIR>\scripts\Stop.ps1
```

**Stop Bayshore and portable PostgreSQL:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <BAYSHORE_DIR>\scripts\Stop.ps1 -IncludeDatabase
```

**Create a database backup:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <BAYSHORE_DIR>\scripts\Backup.ps1
```

**Back up securely:**

- database dumps;
- .env;
- config.json;
- WMMT6.xml;
- AMConfig.ini and WritableConfig.ini;
- bngrw.dll;
- installed certificate/key files;
- MaxiTerminal config.json and executable hash;
- known-working OpenParrot64.dll and its source revision.

Store at least one backup offline. Test how to restore PostgreSQL before an upgrade, not after a failure. Never delete .data\postgres without a verified database backup.

## 20. PORTABLE CHECKLIST FOR A NEW COMPUTER

Use this checklist when reproducing the setup on another computer.

### Before first build

- [ ] Confirm the game is Japanese WMMT6, not 6R/6RR
- [ ] Complete the Section 1 worksheet
- [ ] Create a full game backup
- [ ] Install Node.js 20+, Git, VS C++ tools, SDK, and runtimes
- [ ] Assign/reserve a stable <LAN_IP>
### Server

- [ ] Create .env with a unique random password
- [ ] Set config.json serverIp to <LAN_IP>
- [ ] Install PostgreSQL and deploy migrations
- [ ] Build Bayshore
- [ ] Confirm ready/database ok
### Client

- [ ] Build/install Asakura OpenParrot Release x64
- [ ] Build/install OpenBanapass Release x64
- [ ] Configure AMConfig.ini in Shift-JIS
- [ ] Create WritableConfig.ini
- [ ] Install matching certificate and private key files
- [ ] Configure WMMT6.xml with <LAN_IP>/<ROUTER_IP>
- [ ] Configure WMMT6 MaxiTerminal for revision 10304
- [ ] Customize launcher and multicast-route script paths/IP
### First integrated launch

- [ ] Approve UAC
- [ ] Confirm exactly one MaxiTerminal and AMAuth/MUCHA pair
- [ ] Confirm UDP 50765 sockets
- [ ] Confirm multicast membership on <LAN_ADAPTER>
- [ ] Confirm /wmmt6/resource/file_list in Bayshore log
- [ ] Confirm terminal check passes
- [ ] Test a new virtual card and a saved-card reload
- [ ] Create a database backup

## 21. EXAMPLE WORKSHEET (EXAMPLE ONLY)

> [!NOTE]
> These values are examples only. Do not copy them blindly; they simply demonstrate an internally consistent configuration.

| Placeholder | Example value |
|---|---|
| `<BAYSHORE_DIR>` | `D:\Arcade\Bayshore` |
| `<TEKNOPARROT_DIR>` | `D:\Arcade\TeknoParrot` |
| `<WMMT6_DIR>` | `D:\Arcade\Games\WMMT6` |
| `<AMCUS_DIR>` | `D:\Arcade\Games\WMMT6\AMCUS` |
| `<MAXITERMINAL_DIR>` | `D:\Arcade\Bayshore\bin\MaxiTerminal` |
| `<LAN_IP>` | `192.168.1.50` |
| `<ROUTER_IP>` | `192.168.1.1` |
| `<PREFIX_LENGTH>` | `24` |
| `<DB_USER>` | `bayshore` |
| `<DB_NAME>` | `bayshore` |
| `<DB_PORT>` | `5432` |
| `<ALLNET_PORT>` | `80` |
| `<MUCHA_PORT>` | `10082` |
| `<SERVICE_PORT>` | `9002` |

**Consistent MaxiTerminal server URI:**

```text
https://192.168.1.50:9002
```

**Consistent AMAuth server URL:**

```text
https://192.168.1.50:10082/
```

**Consistent TeknoParrot `NetworkAdapterIP`:**

```text
192.168.1.50
```

## 22. REFERENCES

- **Project Asakura Bayshore:** <https://github.com/ProjectAsakura/Bayshore>
- **Project Asakura legacy setup guide:** <https://github.com/ProjectAsakura/Bayshore/wiki/Setup-guide>
- **Community-updated WMMT6/MaxiTerminal workflow:** <https://github-wiki-see.page/m/kritbualad/Bayshore_WMMT6/wiki/Setup-Guide>
- **Project Asakura organization:** <https://github.com/ProjectAsakura>
- **Project Asakura OpenBanapass:** <https://github.com/ProjectAsakura/OpenBanapass>

---

### End of Universal Guide

Before making changes to a working deployment, back up the database, configuration files, certificates/keys, and known-working client DLLs.

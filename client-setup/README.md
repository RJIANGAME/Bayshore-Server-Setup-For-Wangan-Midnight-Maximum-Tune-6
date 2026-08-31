# Universal WMMT6 Client Configurator

This folder configures a legally obtained Japanese WMMT6 1.03.04 client to use a separate Project Asakura Bayshore server. The client computer does not need Node.js, PostgreSQL, or a full Bayshore server checkout.

## What setup asks for

1. The Bayshore server IPv4 address, such as `192.168.0.25`.
2. A unique drive cabinet number from 1 through 4.
3. The client's WMMT6 `wmn6r.exe`.
4. The client's `TeknoParrotUi.exe`.

The server address is validated before setup continues. The active client IPv4 address and default gateway are detected automatically unless explicit values are placed in `client-config.json`.

## Required assets

The release ZIP includes four verified Bayshore-specific assets: `bngrw.dll`, `setting.lua.gz`, and the certificate/key pair. It does not distribute or overwrite `OpenParrot64.dll`; setup preserves the version supplied by the selected TeknoParrot installation. Setup checks the entire client, every asset, AMCUS configuration, the existing WMMT6 profile, client identity, and network adapter before modifying anything.

Every SHA-256 listed in [assets/README.md](assets/README.md) is verified before changing the client. No runtime file, certificate, or key needs to be selected separately when using the release ZIP.

The WMMT6 game folder must already contain its original `AMCUS` directory, including `AMAuthd.exe`, `AMConfig.ini`, `iauthdll.dll`, and `MuchaBin\muchacd.exe`.
The x64 Microsoft Visual C++ 2010 SP1 runtime (`MSVCR100.dll`) is also required by `iauthdll.dll`; setup checks it during preflight.

## Run

1. Close WMMT6 and TeknoParrot.
2. Right-click `Configure-Client.bat` and select **Run as administrator**.
3. Enter the Bayshore server IPv4 address.
4. Select the correct `wmn6r.exe` and `TeknoParrotUi.exe` when prompted.
5. Wait for `WMMT6 client configuration completed successfully`.
6. Start Bayshore and the single server-side MaxiTerminal.
7. Run `WMMT6-Borderless.bat` from the selected TeknoParrot root.

## What is configured

- the existing TeknoParrot-supplied OpenParrot runtime, preserved unchanged;
- the verified OpenBanapass client file;
- WMMT6 network certificates;
- Shift-JIS-safe `AMConfig.ini` changes for MUCHA;
- `WritableConfig.ini` with a unique drive serial;
- automatic matching of AMAuth `serialID` to the `280811...` auth identity embedded in OpenParrot;
- `WritableConfig.ini` with a unique cabinet `netID` from 1 through 4;
- a persistent, unique client/card identity;
- the existing WMMT6 user profile, automatically corrected with the selected game path, single-executable launching, terminal emulation, card access, the active client adapter, the real router, and stable fullscreen mode;
- removal of obsolete `WMMT6-Bayshore.xml` copies that appeared as a second `Metadata Missing` game;
- Windows hosts entries for ALL.Net;
- the `225.0.0.1/32` multicast route on the active adapter;
- scoped Windows Firewall rules;
- `iauthdll.dll` registration;
- `WMMT6-Borderless.bat` and its helper/config beside `TeknoParrotUi.exe`.

The borderless BAT starts `AMAuthd.exe` directly so OpenParrot is never injected into it, then launches the existing WMMT6 profile through TeknoParrot. OpenParrot's unstable `Windowed` hook stays disabled; the helper repeatedly removes any frame the game recreates and centers a 16:9 surface on the current monitor. Closing the game closes the helper, the AMAuth instance it started, and the backdrop.

Existing files are backed up under `client-setup\backups` before replacement. Do not copy `generated-client-identity.json` or `card.ini` between active cabinets.

For simultaneous play, every computer must use a different cabinet number: cabinet 1 uses `netID=1`, cabinet 2 uses `netID=2`, and so on. A different card ID or drive serial does not replace this requirement. If two clients were configured with an older package, update the package and rerun `Configure-Client.bat` on each computer, selecting a different cabinet number. Only one MaxiTerminal instance should run for the venue.

The supported OpenParrot source contains an AMAuth/terminal identity of `280811990002` and a separate drive-dongle identity beginning with `280813`. `AMCUS\WritableConfig.ini` requires the `280811...` identity. Setup detects that embedded value and writes it automatically. Using `280813...` causes startup error E0517 after ALL.Net and before MUCHA. Leave `DriveSerial` as `AUTO` unless diagnosing a custom build; an explicit value is rejected when it differs from the DLL.

MaxiTerminal is not installed on each client. Normally, one compatible MaxiTerminal instance runs on the server or another designated computer on the same LAN.

## Supported version

This package accepts only the known WMMT6 1.03.04 `wmn6r.exe` hash. It does not support WMMT6R or WMMT6RR.
The configurator refuses the known crashing custom OpenParrot hashes from v1.1.7-v1.2.0. Restore OpenParrot with TeknoParrot's updater or a clean TeknoParrot backup before running v1.3.1.
The package never scans for or automatically selects a ROM when `GamePath` is `SELECT` (the default).

The multicast route is created as an on-link route (`NextHop 0.0.0.0`). Setup
uses the modern Windows networking command first and automatically falls back
to persistent `netsh` or `route.exe` syntax on Windows versions that reject it.

`iauthdll.dll` is registered from its AMCUS working directory. If Windows
rejects re-registration, setup accepts an existing COM registration only when
the registered DLL exists and its SHA-256 matches the selected client's DLL.

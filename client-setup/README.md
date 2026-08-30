# Universal WMMT6 Client Configurator

This folder configures a legally obtained Japanese WMMT6 1.03.04 client to use a separate Project Asakura Bayshore server. The client computer does not need Node.js, PostgreSQL, or a full Bayshore server checkout.

## What setup asks for

1. The Bayshore server IPv4 address, such as `192.168.0.25`.
2. The client's WMMT6 `wmn6r.exe`.
3. The client's `TeknoParrotUi.exe`.

The server address is validated before setup continues. The active client IPv4 address and default gateway are detected automatically unless explicit values are placed in `client-config.json`.

## Required assets

Before running setup, place the five compatible files listed in [assets/README.md](assets/README.md) inside the `assets` folder. They are intentionally not redistributed here. Setup verifies every SHA-256 hash before changing the client.

The WMMT6 game folder must already contain its original `AMCUS` directory, including `AMAuthd.exe`, `AMConfig.ini`, `iauthdll.dll`, and `MuchaBin\muchacd.exe`.

## Run

1. Close WMMT6 and TeknoParrot.
2. Right-click `Configure-Client.bat` and select **Run as administrator**.
3. Enter the Bayshore server IPv4 address.
4. Select the correct `wmn6r.exe` and `TeknoParrotUi.exe` when prompted.
5. Wait for `WMMT6 client configuration completed successfully`.
6. Start the server-side Bayshore and the single venue MaxiTerminal.
7. Run `WMMT6-Borderless.bat` from the selected TeknoParrot root, or launch the configured WMMT6 profile normally.

## What is configured

- verified OpenParrot and OpenBanapass client files;
- WMMT6 network certificates;
- Shift-JIS-safe `AMConfig.ini` changes for MUCHA;
- `WritableConfig.ini` with a unique drive serial;
- a persistent, unique client/card identity;
- TeknoParrot `WMMT6.xml`, including AMAuth startup;
- Windows hosts entries for ALL.Net;
- the `225.0.0.1/32` multicast route on the active adapter;
- scoped Windows Firewall rules;
- `iauthdll.dll` registration;
- `WMMT6-Borderless.bat` and its helper/config beside `TeknoParrotUi.exe`.

The borderless BAT launches the exact configured WMMT6 profile, waits for the selected `wmn6r.exe`, removes the window frame, and centers a 16:9 game surface on its current monitor. A black backdrop fills unused space on non-16:9 displays. Closing the game closes the helper and backdrop automatically.

Existing files are backed up under `client-setup\backups` before replacement. Do not copy `generated-client-identity.json` or `card.ini` between active cabinets.

MaxiTerminal is not installed on each client. Normally, one compatible MaxiTerminal instance runs on the server or another designated computer on the same LAN.

## Supported version

This package accepts only the known WMMT6 1.03.04 `wmn6r.exe` hash. It does not support WMMT6R or WMMT6RR.

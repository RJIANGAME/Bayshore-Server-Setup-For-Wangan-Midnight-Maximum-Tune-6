# Required client assets

The v1.4.1 release ZIP includes the four verified Bayshore-specific files below. `OpenParrot64.dll` is intentionally not included or replaced; use the version supplied by the installed TeknoParrot release.

| File | Required SHA-256 |
|---|---|
| `bngrw.dll` | `1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74` |
| `setting.lua.gz` | `298852A70485DBBAA889739A8A360923DFE7262231AE15CCE758F56ABF8093DD` |
| `server_wangan.crt` | `D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377` |
| `server_wangan.key` | `56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B` |

The configurator verifies all four packaged files, the selected WMMT6/AMCUS
installation, the TeknoParrot profile, client identity, and network adapter
before modifying anything. If a packaged file is removed, setup can still use
a hash-matching copy or ask the user to select one.

Setup preserves the installed TeknoParrot `OpenParrotx64\OpenParrot64.dll`.
It rejects the two custom DLL hashes shipped by client setup v1.1.7-v1.2.0
because crash reports confirmed repeatable native access violations in them.

The configurator never generates a DLL, certificate, or private key. It also
never searches for or automatically selects a WMMT6 ROM.

The release certificate and key form the client terminal trust pair used by
this setup; they are not the Bayshore database password or server `.env` secret.
The DLLs are open-source; their notices and corresponding-source information
are in `../third-party`.

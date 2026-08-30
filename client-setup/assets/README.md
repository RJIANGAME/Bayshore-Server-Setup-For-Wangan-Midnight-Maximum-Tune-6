# Required client assets

The v1.1.9 release ZIP includes all five verified files below. Do not replace them with files from WMMT6R, WMMT6RR, or a standard unrelated TeknoParrot installation.

| File | Required SHA-256 |
|---|---|
| `OpenParrot64.dll` | `BF36B6971738F8B43C400BF07CB422729A8B1065CB429A1978E89782FD09A5E9` |
| `bngrw.dll` | `1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74` |
| `setting.lua.gz` | `298852A70485DBBAA889739A8A360923DFE7262231AE15CCE758F56ABF8093DD` |
| `server_wangan.crt` | `D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377` |
| `server_wangan.key` | `56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B` |

The configurator verifies all five packaged files, the selected WMMT6/AMCUS
installation, the TeknoParrot profile, client identity, and network adapter
before modifying anything. If a packaged file is removed, setup can still use
a hash-matching copy or ask the user to select one.

The configurator never generates a DLL, certificate, or private key. It also
never searches for or automatically selects a WMMT6 ROM.

The release certificate and key form the client terminal trust pair used by
this setup; they are not the Bayshore database password or server `.env` secret.
The DLLs are open-source; their notices and corresponding-source information
are in `../third-party`.

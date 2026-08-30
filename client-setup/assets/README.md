# Required client assets

Supply these files from your own verified build, a trusted existing WMMT6 1.03.04 client, or the corresponding official Project Asakura sources. Do not use files from WMMT6R or WMMT6RR.

| File | Required SHA-256 |
|---|---|
| `OpenParrot64.dll` | `C91922AFAEEBFA9EF81BE2FA532DBCF0E6F4A2DF6EA3C91C5F84AD86D7790952` |
| `bngrw.dll` | `1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74` |
| `setting.lua.gz` | `ECD66886FAED12D6C02178B80EF569FF0570BF8D03770D574866BF42BB681F18` |
| `server_wangan.crt` | `D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377` |
| `server_wangan.key` | `56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B` |

The configurator stops before modifying the client if a file is missing or has a different hash.

Do not commit supplied binaries or key material to this repository. The repository `.gitignore` excludes them.

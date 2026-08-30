# Required client assets

The v1.1.2 release ZIP already includes the two open-source DLLs below. For the remaining files, supply them from your own verified build or a trusted existing WMMT6 1.03.04 client. Do not use files from WMMT6R or WMMT6RR.

| File | Required SHA-256 |
|---|---|
| `OpenParrot64.dll` | `C91922AFAEEBFA9EF81BE2FA532DBCF0E6F4A2DF6EA3C91C5F84AD86D7790952` |
| `bngrw.dll` | `1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74` |
| `setting.lua.gz` | `ECD66886FAED12D6C02178B80EF569FF0570BF8D03770D574866BF42BB681F18` |
| `server_wangan.crt` | `D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377` |
| `server_wangan.key` | `56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B` |

You may place missing files in this folder before setup. If one is absent, the
configurator checks the exact WMMT6/TeknoParrot installation you manually
selected for an existing hash-matching copy. If none is found, it opens a file
picker for that asset. It stops before modifying the client if the selected
file has a different hash.

The configurator never generates a DLL, certificate, or private key. It also
never searches for or automatically selects a WMMT6 ROM.

Do not commit certificates or key material to this repository. The repository
`.gitignore` excludes them. The DLLs distributed in the release are open-source;
their notices and corresponding-source information are in `../third-party`.

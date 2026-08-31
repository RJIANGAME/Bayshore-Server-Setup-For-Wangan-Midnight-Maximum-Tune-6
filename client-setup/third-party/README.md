# Third-party runtime notices

The release ZIP includes one open-source runtime file required by this WMMT6
network configuration. It does not distribute or replace OpenParrot; that core
must come from the client's installed TeknoParrot version.

| Runtime | License | Corresponding source |
|---|---|---|
| `bngrw.dll` (OpenBanapass) | MIT | [ProjectAsakura/OpenBanapass at `21b8ce3`](https://github.com/ProjectAsakura/OpenBanapass/tree/21b8ce3385c4542ccb7fc63c44d574a4b5855250) |

The OpenBanapass build only retargets the Visual Studio project from toolset
v143 to v145; it does not alter the program source. License text is included
beside this notice. This runtime is not game data.

The historical OpenParrot patches remain in the repository for source and
audit history, but their DLL build is not present in v1.3.0.

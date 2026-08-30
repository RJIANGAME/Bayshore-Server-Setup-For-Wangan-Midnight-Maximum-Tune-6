# Third-party runtime notices

The release ZIP includes two open-source runtime files required by this WMMT6
network configuration:

| Runtime | License | Corresponding source |
|---|---|---|
| `OpenParrot64.dll` | GPL-3.0 | [ProjectAsakura/OpenParrot at `4e7b502`](https://github.com/ProjectAsakura/OpenParrot/tree/4e7b502f6422f2c6ec56c57806638e4387b4126a), with [`OpenParrot-WMMT6-network.patch`](OpenParrot-WMMT6-network.patch) |
| `bngrw.dll` (OpenBanapass) | MIT | [ProjectAsakura/OpenBanapass at `21b8ce3`](https://github.com/ProjectAsakura/OpenBanapass/tree/21b8ce3385c4542ccb7fc63c44d574a4b5855250) |

The OpenBanapass build only retargets the Visual Studio project from toolset
v143 to v145; it does not alter the program source. License text is included
beside this notice. Neither runtime is game data.

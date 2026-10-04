# Setup packages v1.7.0

Download both packages from the [GitHub release](https://github.com/RJIANGAME/Bayshore-Server-Setup-For-Wangan-Midnight-Maximum-Tune-6/releases/tag/v1.7.0).

The server package includes Database Editor v1.7.0 with Players & Cars editing,
background database work, search/sort/export, and stale-write protection. Both
packages retain the cabinet selector, Esc exit, and easier LAN setup fixes.

- [Client setup ZIP](Bayshore-WMMT6-Client-Setup-v1.7.0.zip?raw=true)
- [Complete server setup ZIP](Bayshore-WMMT6-Server-Setup-v1.7.0.zip?raw=true)
- [SHA-256 checksums](SHA256SUMS-v1.7.0.txt)
- [Quick start](../QUICK-START.md)

The bundled `server_wangan.key` is the existing public Bayshore compatibility
key from [ProjectAsakura/Bayshore](https://github.com/ProjectAsakura/Bayshore/blob/master/server_wangan.key).
It is not a newly generated or deployment-specific credential. Its content was
compared with that public source before publication: identical after normalizing
CRLF/LF line endings and trimming surrounding whitespace. Both normalized
copies have SHA-256
`45BB8CD715C742172029E402E1BE60E9E5E390466D5FDA9495EAD8960EEC2FAB`.
The packaged CRLF file has SHA-256
`56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B`.

The package builder accepts only the fixed, verified compatibility assets.
It excludes `.env`, deployment configuration, player identities, saves,
database dumps, logs, the game, MaxiTerminal, and OpenParrot.

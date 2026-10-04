"""Build setup ZIPs from explicit sources; never include a running server's saves/secrets."""
import argparse
import hashlib
from pathlib import Path
import zipfile

ASSETS = {
    'bngrw.dll': '1B4222AA81F55E020CEDFF1A254A32F5F6F7B0CE5D67D88E71134C52F3941E74',
    'setting.lua.gz': '298852A70485DBBAA889739A8A360923DFE7262231AE15CCE758F56ABF8093DD',
    'server_wangan.crt': 'D3A67BD19DCE52D8062EA5D83A555311B25DD675010B6E7B49D60FA42AB6E377',
    'server_wangan.key': '56ABEB63F00A04D54D709253E5F0F13B35ED72D4C41262A0A40F8D8BEF557C2B',
}
APP_FILES = (
    'package.json', 'package-lock.json', 'tsconfig.json', 'tsconfig.proto.json',
    '.env.example', 'config.example.json', 'LICENSE',
    'scripts/Setup.ps1', 'scripts/Start.ps1', 'scripts/Stop.ps1',
    'scripts/Configure-Firewall.ps1', 'scripts/HealthCheck.ps1', 'scripts/Start-MaxiTerminal.ps1',
)


def source_files(root, folder):
    for path in sorted((root / folder).rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if any(p in {'backups', '__pycache__', '.git'} for p in relative.parts):
            continue
        if path.suffix in {'.log', '.pid', '.bak', '.pyc'}:
            continue
        if path.name in {'generated-client-identity.json', 'server-terminal.json'}:
            continue
        yield relative.as_posix(), path.read_bytes()


def write_zip(path, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, content in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (2026, 10, 4, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            output.writestr(info, content)
    with zipfile.ZipFile(path) as check:
        if check.testzip():
            raise ValueError(f'Corrupt archive: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bayshore-root', type=Path, required=True)
    parser.add_argument('--setup-root', type=Path, required=True)
    parser.add_argument('--asset-zip', type=Path, required=True)
    parser.add_argument('--version', default='1.6.0')
    args = parser.parse_args()
    assets = {}
    with zipfile.ZipFile(args.asset_zip) as previous:
        for name, expected in ASSETS.items():
            entry = next(p for p in previous.namelist() if p.replace('\\', '/').endswith('/assets/' + name))
            data = previous.read(entry)
            if hashlib.sha256(data).hexdigest().upper() != expected:
                raise ValueError(f'Asset hash mismatch: {name}')
            assets[name] = data
    client = dict(source_files(args.setup_root, 'client-setup'))
    for name, data in assets.items():
        client['client-setup/assets/' + name] = data
    server = {}
    for folder in ('server-terminal-setup', 'server-setup', 'server-tools', 'database-editor'):
        server.update(source_files(args.setup_root, folder))
    for name in ('Configure-Server.bat', 'Backup-Player-Data.bat', 'Restore-Player-Data.bat', 'Merge-Player-Data.bat', 'Bayshore-Database-Editor.bat', 'QUICK-START.md'):
        server[name] = (args.setup_root / name).read_bytes()
    for name in APP_FILES:
        server['server/' + name] = (args.bayshore_root / name).read_bytes()
    for folder in ('src', 'prisma'):
        server.update({'server/' + name: data for name, data in source_files(args.bayshore_root, folder)})
    for name in ('server_wangan.crt', 'server_wangan.key'):
        server['server/' + name] = assets[name]
    # Include the project's public license, not any local config or credentials.
    server['server/README.md'] = (args.bayshore_root / 'README.md').read_bytes()
    output_root = args.setup_root / 'releases'
    output_root.mkdir(exist_ok=True)
    records = []
    for label, entries in (('Client', client), ('Server', server)):
        name = f'Bayshore-WMMT6-{label}-Setup-v{args.version}.zip'
        digest = write_zip(output_root / name, entries)
        records.append(f'{digest}  {name}')
        print(f'{name}: {(output_root / name).stat().st_size:,} bytes, {len(entries)} files')
    (output_root / f'SHA256SUMS-v{args.version}.txt').write_text('\n'.join(records) + '\n', encoding='ascii')


if __name__ == '__main__':
    main()

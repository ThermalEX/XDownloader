"""Generate release metadata from verified APK bytes; never signs or edits APKs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile

OFFICIAL_CERTIFICATE = 'bffe0baa0876c1c6579bb5cf39b04cdc6c0fcd2ca4ffd349fef6e1a01153a104'
MAX_BYTES = 200 * 1024 * 1024
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'}
PROBE_MARKERS = (b'probeSeed', b'probeDelete', b'probeVerifyUpdate', b'probeLoadUpdateFixtures',
                 b'probeStageReadyUpdate', b'probeClearReadyUpdate', b'probeCanInstallUpdates',
                 b'probeReturnToApp', b'probeUpdateRecovery', b'probeReplaceLegacy')

class ManifestError(Exception):
    pass

def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def parse_badging(text):
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", text, re.M)
    sdk = re.search(r"^(?:sdkVersion|minSdkVersion):'(\d+)'", text, re.M)
    if not package or not sdk:
        raise ManifestError('Cannot read APK package/version/minSdk')
    return {'packageName': package[1], 'versionCode': int(package[2]),
            'versionName': package[3], 'minSdk': int(sdk[1])}

def inspect_apk(path, aapt2, apksigner):
    badging = subprocess.check_output([str(aapt2), 'dump', 'badging', str(path)], stderr=subprocess.PIPE).decode('utf-8')
    metadata = parse_badging(badging)
    verification = subprocess.check_output([str(apksigner), 'verify', '--verbose', '--print-certs', str(path)], stderr=subprocess.PIPE).decode('utf-8')
    certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})\r?$', verification, re.M)
    if len(certificates) != 1:
        raise ManifestError('APK must have one verified signer')
    metadata['certificate'] = certificates[0].lower()
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if any('update_probe_fixtures' in name for name in names):
            raise ManifestError('Probe assets found in production APK')
        for name in names:
            if re.fullmatch(r'classes\d*\.dex', name):
                dex = archive.read(name)
                if any(marker in dex for marker in PROBE_MARKERS):
                    raise ManifestError('Probe methods found in production APK')
        abis = sorted({name.split('/')[1] for name in names if re.fullmatch(r'lib/[^/]+/libapp\.so', name)})
        if not abis or any('lib/' + abi + '/libflutter.so' not in names for abi in abis):
            raise ManifestError('Missing release Flutter native libraries')
        metadata['abis'] = abis
    return metadata

def build_manifest(paths, channel, tag, *, inspect, max_bytes=MAX_BYTES, expected_certificate=OFFICIAL_CERTIFICATE):
    if channel not in ('stable', 'beta') or not paths:
        raise ManifestError('Expected stable/beta channel and at least one APK')
    assets, baseline, names, abi_sets = [], None, set(), set()
    for value in paths:
        path = Path(value)
        if not path.is_file() or path.is_symlink() or not 0 < path.stat().st_size <= max_bytes:
            raise ManifestError('Missing/oversized APK: ' + path.name)
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*\.apk', path.name) or path.name in names:
            raise ManifestError('Invalid or duplicate APK name')
        names.add(path.name)
        metadata = inspect(path)
        if metadata['packageName'] != 'com.xdl.app' or metadata['certificate'] != expected_certificate:
            raise ManifestError('Wrong APK package or signing certificate')
        if not 0 < metadata['versionCode'] < 2 ** 31 or metadata['minSdk'] < 26:
            raise ManifestError('Invalid APK versionCode/minSdk')
        current = {key: metadata[key] for key in ('packageName', 'versionName', 'versionCode', 'minSdk', 'certificate')}
        if baseline is None:
            baseline = current
        elif current != baseline:
            raise ManifestError('APK variants disagree on package/version/minSdk/signature')
        version = metadata['versionName']
        if tag != 'v' + version or not re.fullmatch(r'\d+\.\d+\.\d+(?:-beta\.\d+)?', version) or (channel == 'beta') != ('-beta.' in version):
            raise ManifestError('Channel/tag/APK version mismatch')
        abis = metadata['abis']
        if not abis or len(abis) != len(set(abis)) or not set(abis) <= ABIS or tuple(sorted(abis)) in abi_sets:
            raise ManifestError('Invalid or duplicate ABI set')
        abi_sets.add(tuple(sorted(abis)))
        assets.append({'name': path.name, 'abis': sorted(abis), 'bytes': path.stat().st_size, 'sha256': sha256(path)})
    return {'schema': 1, 'versionName': baseline['versionName'], 'versionCode': baseline['versionCode'],
            'channel': channel, 'packageName': baseline['packageName'], 'minSdk': baseline['minSdk'], 'assets': assets}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--channel', choices=['stable', 'beta'], required=True)
    p.add_argument('--tag', required=True)
    p.add_argument('--apk', type=Path, action='append', required=True)
    p.add_argument('--aapt2', type=Path, required=True)
    p.add_argument('--apksigner', type=Path, required=True)
    p.add_argument('--expected-certificate', default=OFFICIAL_CERTIFICATE)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    try:
        if args.output.exists() and any(args.output.iterdir()):
            raise ManifestError('Output directory must be empty; published metadata is immutable')
        manifest = build_manifest(args.apk, args.channel, args.tag,
            inspect=lambda path: inspect_apk(path, args.aapt2, args.apksigner), expected_certificate=args.expected_certificate.lower())
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'update.json').write_bytes((json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
        (args.output / 'SHA256SUMS.txt').write_bytes(('\n'.join(a['sha256'] + '  ' + a['name'] for a in manifest['assets']) + '\n').encode('utf-8'))
        print(f'Validated {len(manifest["assets"])} APKs; {manifest["versionName"]}/{manifest["versionCode"]} {args.channel} metadata ready.')
    except (ManifestError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        p.exit(1, f'Release metadata failed: {exc}\n')

if __name__ == '__main__':
    main()

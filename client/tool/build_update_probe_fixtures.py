"""Build small signed, test-only APKs. Never edits the production signing key."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--key-properties', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--code', type=int, default=999998)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    props = dict(line.strip().split('=', 1) for line in args.key_properties.read_text().splitlines()
                 if '=' in line and not line.lstrip().startswith('#'))
    tools = args.sdk / 'build-tools' / '36.0.0'
    env = os.environ.copy()
    env['XDL_FIXTURE_STORE'] = props['storePassword']
    env['XDL_FIXTURE_KEY'] = props['keyPassword']
    java_home = Path(env['JAVA_HOME'])
    wrong_key = args.output / 'fixture-only.jks'
    subprocess.run([str(java_home / 'bin/keytool.exe'), '-genkeypair', '-keystore', str(wrong_key),
                    '-storepass', 'fixture-only', '-keypass', 'fixture-only', '-alias', 'fixture',
                    '-keyalg', 'RSA', '-validity', '2', '-dname', 'CN=XDownloader Test Only'], check=True, capture_output=True)
    fixtures = []
    android = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', android)
    for name, package, code, minimum, wrong in [
        ('valid', 'com.xdl.app.probe', args.code, 26, False),
        ('package', 'com.xdl.fixture.other', args.code, 26, False),
        ('old', 'com.xdl.app.probe', 1, 26, False),
        ('signer', 'com.xdl.app.probe', args.code, 26, True),
        ('sdk', 'com.xdl.app.probe', args.code, 28, False),
    ]:
        xml = ET.Element('manifest', {'package': package, f'{{{android}}}versionCode': str(code),
                                    f'{{{android}}}versionName': '2.5.0'})
        ET.SubElement(xml, 'uses-sdk', {f'{{{android}}}minSdkVersion': str(minimum), f'{{{android}}}targetSdkVersion': '36'})
        ET.SubElement(xml, 'application', {f'{{{android}}}hasCode': 'false', f'{{{android}}}label': 'Update probe fixture'})
        manifest = args.output / f'{name}.xml'
        manifest.write_bytes(ET.tostring(xml, encoding='utf-8', xml_declaration=True))
        apk = args.output / f'{name}.apk'
        subprocess.run([str(tools / 'aapt2.exe'), 'link', '-I', str(args.sdk / 'platforms/android-36/android.jar'),
                        '--manifest', str(manifest), '-o', str(apk)], check=True, capture_output=True)
        key = wrong_key if wrong else Path(props['storeFile'])
        subprocess.run([str(tools / 'apksigner.bat'), 'sign', '--ks', str(key), '--ks-key-alias', 'fixture' if wrong else props['keyAlias'],
                        '--ks-pass', 'pass:fixture-only' if wrong else 'env:XDL_FIXTURE_STORE',
                        '--key-pass', 'pass:fixture-only' if wrong else 'env:XDL_FIXTURE_KEY', str(apk)], check=True, env=env, capture_output=True)
        data = apk.read_bytes()
        expected = {'packageName': 'com.xdl.app.probe', 'versionName': '2.5.0', 'versionCode': args.code,
                    'minSdk': 26, 'asset': {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}}
        fixtures.append({'label': name, 'data': base64.b64encode(data).decode(), 'expected': expected, 'success': name == 'valid'})
    valid = fixtures[0]
    for name, changes in [('hash', {'sha256': '0' * 64}), ('bytes', {'bytes': valid['expected']['asset']['bytes'] + 1})]:
        expected = {**valid['expected'], 'asset': {**valid['expected']['asset'], **changes}}
        fixtures.append({**valid, 'label': name, 'expected': expected, 'success': False})
    fixtures.append({**valid, 'label': 'replaced-after-verify', 'replaceAfterVerification': True, 'success': False})
    target = args.output / 'fixtures.json'
    target.write_text(json.dumps(fixtures), encoding='utf-8')
    print(f'Created {len(fixtures)} APK validation cases: {target}')

if __name__ == '__main__':
    main()

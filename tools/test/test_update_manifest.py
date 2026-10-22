import importlib.util
from pathlib import Path
import hashlib
import tempfile
import unittest
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('update_manifest', Path(__file__).parents[1] / 'make_update_manifest.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class UpdateManifestTest(unittest.TestCase):
    def test_changelog_publishes_body_without_duplicate_release_heading(self):
        source = '# XDownloader 2.11.0\n\n## 重要修复\n\n- **内容**\n\n## XDownloader 2.10.0\n\n- 旧内容\n'
        self.assertEqual(module.notes_from_changelog(source, '2.11.0'), '## 重要修复\n\n- **内容**\n')
        self.assertEqual(module.notes_from_changelog('# XDownloader 2.11.0\n\n- 内容\n', '2.11.0'), '- 内容\n')
        with self.assertRaises(module.ManifestError): module.notes_from_changelog(source, '2.10.0')
        with self.assertRaises(module.ManifestError): module.notes_from_changelog('# XDownloader 2.11.0\n', '2.11.0')
    def test_cli_changelog_validation_happens_before_metadata_output(self):
        for correct in [True, False]:
            changelog=self.root / 'CHANGELOG.md'
            changelog.write_text('# XDownloader ' + ('2.5.0' if correct else '2.4.0') + '\n\n- Change\n', encoding='utf-8')
            output=self.root / ('valid' if correct else 'invalid')
            args=['make_update_manifest.py', '--channel', 'stable', '--tag', 'v2.5.0',
                  '--aapt2', 'fixture', '--apksigner', 'fixture', '--output', str(output), '--changelog', str(changelog)]
            for path in self.paths: args += ['--apk', str(path)]
            with patch.object(sys, 'argv', args), patch.object(module, 'inspect_apk', side_effect=lambda path, *_args: self.inspect(path)):
                if correct:
                    module.main()
                    self.assertEqual((output/'RELEASE_NOTES.md').read_text(encoding='utf-8'), '- Change\n')
                else:
                    with self.assertRaises(SystemExit): module.main()
                    self.assertFalse(output.exists())
    def test_version_heading_inside_fenced_examples_does_not_truncate_notes(self):
        for opening, closing in [('```markdown', '```'), ('~~~~', '~~~~~')]:
            body=f'- Current\n\n{opening}\n## XDownloader 2.10.0\n{closing}\n\n- After example\n'
            source='# XDownloader 2.11.0\n\n' + body + '\n## XDownloader 2.10.0\n\n- Older\n'
            self.assertEqual(module.notes_from_changelog(source, '2.11.0'), body)
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='xdl-manifest-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.paths = [self.root / 'XDownloader-2.5.0-arm64-v8a.apk', self.root / 'XDownloader-2.5.0.apk']
        for index, path in enumerate(self.paths): path.write_bytes(b'fixture-apk-' + bytes([index]))
        self.meta = {'packageName': 'com.xdl.app', 'versionName': '2.5.0', 'versionCode': 15,
                     'minSdk': 26, 'certificate': module.OFFICIAL_CERTIFICATE}
    def inspect(self, path):
        return {**self.meta, 'abis': ['arm64-v8a'] if 'arm64' in path.name else ['arm64-v8a', 'armeabi-v7a', 'x86_64']}
    def build(self, **kwargs):
        return module.build_manifest(self.paths, 'stable', 'v2.5.0', inspect=kwargs.pop('inspect', self.inspect), **kwargs)
    def test_manifest_matches_apk_bytes_and_metadata(self):
        manifest = self.build()
        self.assertEqual(manifest['versionCode'], 15)
        self.assertEqual(manifest['schema'], 1)
        for asset, path in zip(manifest['assets'], self.paths):
            self.assertEqual(asset['bytes'], path.stat().st_size)
            self.assertEqual(asset['sha256'], hashlib.sha256(path.read_bytes()).hexdigest())
    def test_rejects_version_certificate_package_and_abi_mismatch(self):
        for field, value in [('versionCode', 16), ('versionName', '2.5.1'), ('packageName', 'com.xdl.app.probe'),
                             ('certificate', '0' * 64), ('minSdk', 27)]:
            def different(path, field=field, value=value):
                return {**self.inspect(path), **({field: value} if path == self.paths[1] else {})}
            with self.assertRaises(module.ManifestError): self.build(inspect=different)
        with self.assertRaises(module.ManifestError):
            self.build(inspect=lambda path: {**self.inspect(path), 'abis': ['riscv64']})
        with self.assertRaises(module.ManifestError):
            module.build_manifest([self.paths[0], self.paths[0]], 'stable', 'v2.5.0', inspect=self.inspect)
    def test_rejects_channel_tag_mismatch_and_oversize(self):
        for channel, tag in [('beta', 'v2.5.0'), ('stable', 'v2.6.0')]:
            with self.assertRaises(module.ManifestError): module.build_manifest(self.paths, channel, tag, inspect=self.inspect)
        with self.assertRaises(module.ManifestError): self.build(max_bytes=1)
    def test_cli_metadata_parser_uses_verified_production_apk(self):
        badging = "package: name='com.xdl.app' versionCode='15' versionName='2.5.0'\nsdkVersion:'26'\n"
        self.assertEqual(module.parse_badging(badging)['versionCode'], 15)
        with self.assertRaises(module.ManifestError): module.parse_badging('not an APK')

    def test_accepts_build_tools_36_min_sdk_badging(self):
        badging = "package: name='com.xdl.app' versionCode='15' versionName='2.5.0'\nminSdkVersion:'26'\ntargetSdkVersion:'36'\n"
        self.assertEqual(module.parse_badging(badging)['minSdk'], 26)

    def test_windows_signer_output_is_accepted(self):
        import zipfile
        path = self.root / 'production.apk'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('lib/arm64-v8a/libapp.so', b'code')
            archive.writestr('lib/arm64-v8a/libflutter.so', b'engine')
        outputs = [b"package: name='com.xdl.app' versionCode='15' versionName='2.5.0'\r\nminSdkVersion:'26'\r\n",
                   ('Verifies\r\nSigner #1 certificate SHA-256 digest: ' + module.OFFICIAL_CERTIFICATE + '\r\n').encode()]
        with patch.object(module.subprocess, 'check_output', side_effect=outputs):
            self.assertEqual(module.inspect_apk(path, 'aapt2', 'apksigner')['certificate'], module.OFFICIAL_CERTIFICATE)

if __name__ == '__main__': unittest.main()

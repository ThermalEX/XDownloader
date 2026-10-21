import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).parents[1] / 'export_public.py'
spec = importlib.util.spec_from_file_location('public_export', MODULE)
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)

class PublicExportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='xdl-export-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        for name in exporter.TEMPLATES:
            self.write('tools/public_templates/' + name, 'Public fixture\n')
        self.write('client/lib/main.dart', 'void main() {}\n')
        self.write('tools/public_files.txt', '\n'.join(
            ['client/lib/main.dart', 'tools/public_files.txt'] +
            ['tools/public_templates/' + name for name in exporter.TEMPLATES]) + '\n')
        self.commit()
    def git(self, *args, root=None):
        return subprocess.check_output(['git', '-C', str(root or self.source), *args], stderr=subprocess.DEVNULL).decode().strip()
    def write(self, name, value):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value, encoding='utf-8')
    def commit(self):
        self.git('add', '--all'); self.git('commit', '-qm', 'fixture')
    def export(self):
        destination = self.root / 'public'
        exporter.export_public(self.source, 'HEAD', destination)
        return destination
    def test_export_has_no_private_ancestors(self):
        self.write('.codex-remote-attachments/private.jpg', 'private attachment')
        self.commit()
        private_blob = self.git('rev-parse', 'HEAD:.codex-remote-attachments/private.jpg')
        self.git('rm', '.codex-remote-attachments/private.jpg'); self.commit()
        self.assertTrue(any('private.jpg' in issue for issue in exporter.verify_public(self.source)))
        target = self.export()
        self.git('init', '-b', 'main', root=target)
        self.git('add', '.', root=target)
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'public', root=target)
        self.assertEqual(self.git('rev-list', '--all', '--count', root=target), '1')
        self.assertNotIn(private_blob, self.git('rev-list', '--all', '--objects', root=target))
        self.assertEqual(exporter.verify_public(target), [])
    def test_rejects_key_inside_allowed_directory(self):
        self.write('client/android/key.properties', 'storePassword=private')
        self.commit()
        with self.assertRaises(exporter.ExportError): self.export()
    def test_rejects_symlink_and_nonempty_destination(self):
        target = self.root / 'public'; target.mkdir(); (target / 'keep').write_text('keep')
        with self.assertRaises(exporter.ExportError): exporter.export_public(self.source, 'HEAD', target)
        self.assertEqual((target / 'keep').read_text(), 'keep')
        # Git's index mode models a symlink without needing Windows symlink privileges.
        blob = subprocess.check_output(['git', '-C', str(self.source), 'hash-object', '-w', '--stdin'], input=b'../../private').decode().strip()
        self.git('update-index', '--add', '--cacheinfo', '120000,' + blob + ',client/lib/link.dart')
        self.git('commit', '-qm', 'symlink')
        with self.assertRaises(exporter.ExportError): exporter.export_public(self.source, 'HEAD', self.root / 'other')
    def test_unknown_file_is_not_silently_published(self):
        self.write('client/lib/unreviewed.bin', 'unexpected')
        self.commit()
        with self.assertRaises(exporter.ExportError): self.export()
    def test_new_text_paths_require_explicit_review(self):
        for suffix in ['json', 'md', 'properties']:
            self.write('client/test/fixtures/session.' + suffix, 'private session')
            self.commit()
            with self.assertRaises(exporter.ExportError): self.export()
    def test_export_retains_all_source_apks_byte_for_byte(self):
        self.write('releases/old.apk', 'preserve bytes')
        self.commit()
        before = (self.source / 'releases/old.apk').read_bytes()
        head = self.git('rev-parse', 'HEAD')
        target = self.export()
        self.assertFalse((target / 'releases/old.apk').exists())
        self.assertEqual((self.source / 'releases/old.apk').read_bytes(), before)
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)
    def test_secret_and_personal_path_rejected_without_echoing_secret(self):
        for value in ['ghp_' + 'x' * 30, 'F:' + '/project/private']:
            self.write('client/lib/main.dart', value); self.commit()
            with self.assertRaises(exporter.ExportError) as found: self.export()
            self.assertNotIn(value, str(found.exception))

if __name__ == '__main__': unittest.main()

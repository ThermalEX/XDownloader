"""Export a reviewed source snapshot, without sharing private Git ancestors."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

TEMPLATES = {
    'README.md': 'README.md', 'BUILDING.md': 'BUILDING.md',
    'AGENTS.md': 'AGENTS.md', '.gitignore': '.gitignore', '.gitattributes': '.gitattributes',
    'key.properties.example': 'client/android/key.properties.example',
    'CLIENT_AGENTS.md': 'client/AGENTS.md',
}
ROOT_FILES = {'client/.gitignore', 'client/.metadata', 'client/analysis_options.yaml',
              'client/pubspec.yaml', 'client/pubspec.lock', 'client/AGENTS.md',
              'client/assets/branding/app_icon.png'}
ICON_FOREGROUNDS = {'client/android/app/src/main/res/drawable-' + density + '/ic_launcher_foreground.png'
                    for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')}
PREFIXES = ('client/lib/', 'client/test/', 'client/integration_test/', 'client/tool/', 'client/android/')
INVENTORY = 'tools/public_files.txt'
TOOLS = {INVENTORY, 'tools/export_public.py', 'tools/make_update_manifest.py',
         'tools/test/test_public_export.py', 'tools/test/test_update_manifest.py'}
DESIGN = 'docs/superpowers/specs/2026-10-21-updates-history-design.md'
SUFFIXES = {'.dart', '.kt', '.xml', '.kts', '.properties', '.py', '.json', '.html', '.yaml', '.lock', '.md'}
FORBIDDEN_SUFFIXES = {'.apk', '.jks', '.keystore', '.pem', '.p12', '.pfx', '.log'}
PRIVATE = re.compile(r'(?i)(?:[A-Z]:[/\\](?:Users|project|software)\b|\b\d{5}FDKX[A-Z0-9]{5}\b)')
SECRETS = re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|'
                     r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|AIza[A-Za-z0-9_-]{30,})')

class ExportError(Exception):
    pass

def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)

def valid_path(path):
    parts = PurePosixPath(path).parts
    return bool(parts) and not path.startswith('/') and all(p not in ('..', '.') for p in parts) and '\\' not in path and ':' not in path

def allowed(path):
    if not valid_path(path):
        raise ExportError('Unsafe repository path')
    if path in TOOLS or path == DESIGN or path in ROOT_FILES:
        return True
    if path.startswith('tools/public_templates/') and path.removeprefix('tools/public_templates/') in TEMPLATES:
        return True
    if not path.startswith(PREFIXES):
        return False
    name = PurePosixPath(path).name
    suffix = PurePosixPath(path).suffix.lower()
    if name in ('key.properties', 'local.properties', '.env') or name.startswith('.env.') or suffix in FORBIDDEN_SUFFIXES:
        raise ExportError('Forbidden public file: ' + path)
    if suffix == '.png':
        if path in ICON_FOREGROUNDS or (path.startswith('client/android/app/src/main/res/mipmap-') and name == 'ic_launcher.png'):
            return True
        raise ExportError('Unreviewed binary file: ' + path)
    if suffix in SUFFIXES or name == '.gitignore':
        return True
    raise ExportError('Unreviewed file type: ' + path)

def scan(path, content):
    if path.endswith('.png'):
        if not content.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ExportError('Invalid launcher image: ' + path)
        return
    try:
        text = content.decode('utf-8')
    except UnicodeDecodeError as exc:
        raise ExportError('Non-UTF8 public source: ' + path) from exc
    for number, line in enumerate(text.splitlines(), 1):
        if PRIVATE.search(line) or SECRETS.search(line):
            raise ExportError(f'Sensitive content in {path}:{number}')

def tree(root, ref):
    for record in git(root, 'ls-tree', '-r', '-z', '--full-tree', ref).split(b'\0'):
        if record:
            metadata, name = record.split(b'\t', 1)
            mode, kind, oid = metadata.decode().split()
            yield mode, kind, oid, name.decode('utf-8')


def reviewed_paths(root, ref):
    try:
        paths = git(root, 'show', ref + ':' + INVENTORY).decode('utf-8').splitlines()
    except (subprocess.CalledProcessError, UnicodeDecodeError) as exc:
        raise ExportError('Missing reviewed public file inventory') from exc
    if len(paths) != len(set(paths)) or any(not valid_path(path) or not allowed(path) for path in paths):
        raise ExportError('Invalid reviewed public file inventory')
    return set(paths)

def export_public(source, ref, destination):
    source = Path(source).resolve()
    destination = Path(destination).resolve()
    if destination == source or source.is_relative_to(destination):
        raise ExportError('Destination cannot contain or replace source')
    if destination.exists() and any(destination.iterdir()):
        raise ExportError('Destination must be empty')
    commit = git(source, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()
    reviewed = reviewed_paths(source, commit)
    outputs, skipped = {}, []
    replaced = set(TEMPLATES.values())
    for mode, kind, oid, path in tree(source, commit):
        if path in replaced:
            continue
        if not allowed(path):
            skipped.append(path)
            continue
        if path not in reviewed:
            raise ExportError('Undeclared public file: ' + path)
        if mode not in ('100644', '100755') or kind != 'blob':
            raise ExportError('Public export rejects symlink/submodule: ' + path)
        content = git(source, 'cat-file', 'blob', oid)
        if path == DESIGN:
            text = content.decode('utf-8').replace(str(source), '<workspace>').replace(source.as_posix(), '<workspace>')
            content = text.encode('utf-8')
        scan(path, content)
        outputs[path] = content
    for name, target in TEMPLATES.items():
        if 'tools/public_templates/' + name not in reviewed:
            raise ExportError('Undeclared public template: ' + name)
        content = git(source, 'show', commit + ':tools/public_templates/' + name)
        scan(target, content)
        outputs[target] = content
    outputs['PUBLIC_PROVENANCE.json'] = (json.dumps({'schema': 1, 'sourceCommit': commit,
                                                   'exportRules': 1}, indent=2) + '\n').encode()
    outputs['PUBLIC_FILES.sha256'] = ('\n'.join(hashlib.sha256(data).hexdigest() + '  ' + name
        for name, data in sorted(outputs.items())) + '\n').encode()
    # Validate the whole export before writing a single destination file.
    destination.mkdir(parents=True, exist_ok=True)
    for path, content in outputs.items():
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    return skipped

def verify_public(root):
    issues, scanned = [], set()
    extras = set(TEMPLATES.values()) | {'PUBLIC_FILES.sha256', 'PUBLIC_PROVENANCE.json'}
    for commit in git(root, 'rev-list', '--all').decode().splitlines():
        try:
            reviewed = reviewed_paths(root, commit)
        except ExportError as exc:
            issues.append(str(exc))
            reviewed = set()
        for mode, kind, oid, path in tree(root, commit):
            try:
                if path not in extras and not allowed(path):
                    raise ExportError('Private path in reachable public history: ' + path)
                if path not in extras and path not in reviewed:
                    raise ExportError('Undeclared public file: ' + path)
                if mode not in ('100644', '100755') or kind != 'blob':
                    raise ExportError('Non-file in public history: ' + path)
                if (oid, path) not in scanned:
                    scan(path, git(root, 'cat-file', 'blob', oid))
                    scanned.add((oid, path))
            except ExportError as exc:
                issues.append(str(exc))
    return sorted(set(issues))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--ref')
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--verify-public', type=Path)
    args = parser.parse_args()
    try:
        if args.verify_public:
            issues = verify_public(args.verify_public)
            if issues:
                raise ExportError('\n'.join(issues))
            print('Public reachable history scan passed.')
        else:
            if not all((args.source, args.ref, args.destination)):
                parser.error('--source, --ref and --destination are required')
            skipped = export_public(args.source, args.ref, args.destination)
            print(f'Exported reviewed snapshot; {len(skipped)} private/non-delivery paths omitted.')
    except (ExportError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f'Public export failed: {exc}\n')

if __name__ == '__main__':
    main()

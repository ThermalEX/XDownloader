import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/backup/backup_archive.dart';

BackupArchive archive(Map<String, Map<String, Object?>> data) =>
    BackupArchive.create(
      id: 'archive-1',
      createdAt: DateTime.utc(2026, 11, 1, 12, 13, 14, 15),
      deviceId: 'device-1',
      deviceName: '测试手机',
      appVersion: '2.16.0',
      data: data,
    );

Map<String, Object?> favorite(String id) => {
  'postId': id,
  'url': 'https://x.com/i/status/$id',
  'title': 'title',
  'category': '分类',
  'createdAt': '2026-11-01T00:00:00.000Z',
  'author': 'author',
  'coverUrl': 'https://example.com/cover.jpg',
};

void main() {
  test('split ZIP rejects missing modified and unregistered documents or binary files', () {
    final original = BackupArchive.create(
      id: 'test',
      deviceId: 'phone',
      deviceName: 'phone',
      createdAt: DateTime.utc(2026),
      appVersion: 'test',
      data: {
        'favorites': {'items': []},
        'settings': {},
      },
      files: {
        'images/test.bin': [1, 2, 3],
      },
    );
    final entries = {
      for (final file in ZipDecoder().decodeBytes(original.encode()).files)
        file.name: List<int>.of(file.content),
    };
    List<int> repack(Map<String, List<int>> files) {
      final archive = Archive();
      for (final entry in files.entries) {
        archive.add(ArchiveFile(entry.key, entry.value.length, entry.value));
      }
      return ZipEncoder().encode(archive);
    }

    final missing = {...entries}..remove('settings.json');
    expect(() => BackupArchive.decode(repack(missing)), throwsFormatException);
    final modified = {
      ...entries,
      'favorites.json': utf8.encode('{"items":[],"categories":["new"]}'),
    };
    expect(() => BackupArchive.decode(repack(modified)), throwsFormatException);
    final binary = {
      ...entries,
      'files/images/test.bin': [3, 2, 1],
    };
    expect(() => BackupArchive.decode(repack(binary)), throwsFormatException);
    final unknown = {
      ...entries,
      'unregistered.json': [123, 125],
    };
    expect(() => BackupArchive.decode(repack(unknown)), throwsFormatException);
    expect(
      () =>
          BackupArchive.decode(utf8.encode('{"format":"xdownloader.backup"}')),
      throwsFormatException,
    );
  });
  test(
    'split document ZIP bytes remain identical after decoding unordered groups',
    () {
      final value = archive({
        'updates': {},
        'sources': {},
        'settings': {},
        'favorites': {'items': []},
      });
      final bytes = value.encode();
      expect(BackupArchive.decode(bytes).encode(), bytes);
    },
  );
  test('selected sections are independent JSON files and manifest has no inline data', () {
    final value = archive({
      'favorites': {
        'items': [favorite('12345')],
      },
      'settings': {},
      'sources': {},
      'updates': {},
    });
    final zip = ZipDecoder().decodeBytes(value.encode());
    expect(zip.files.map((f) => f.name).toSet(), {
      'manifest.json',
      'favorites.json',
      'settings.json',
      'sources.json',
      'updates.json',
    });
    final manifest =
        jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content)) as Map;
    expect(manifest.containsKey('data'), false);
    final favorites =
        jsonDecode(utf8.decode(zip.findFile('favorites.json')!.content)) as Map;
    expect((favorites['items'] as List).single, favorite('12345'));
    final partial = ZipDecoder().decodeBytes(archive({'sources': {}}).encode());
    expect(partial.files.map((f) => f.name).toSet(), {
      'manifest.json',
      'sources.json',
    });
  });
  test(
    'ZIP container preserves optional binary files alongside backup JSON',
    () {
      final extra = <String, List<int>>{
        'images/cover.png': [0, 1, 128, 255],
      };
      final value = BackupArchive.create(
        id: 'id',
        deviceId: 'phone',
        deviceName: 'Pixel 11 Pro',
        createdAt: DateTime.utc(2026, 11, 2),
        appVersion: 'test',
        data: {
          'favorites': {'items': []},
        },
        files: extra,
      );
      extra['images/cover.png']![0] = 99;
      final bytes = value.encode();
      expect(bytes.take(2), [0x50, 0x4b]);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(
        zip.files.map((f) => f.name),
        containsAll([
          'manifest.json',
          'favorites.json',
          'files/images/cover.png',
        ]),
      );
      final decoded = BackupArchive.decode(bytes);
      expect(decoded.files['images/cover.png'], [0, 1, 128, 255]);
      expect(decoded.encode(), bytes);
      expect(value.fileName, endsWith('.zip'));
      expect(
        () => decoded.files['images/cover.png']![0] = 3,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'explicit null source fallback is rejected while absent uses defaults',
    () {
      expect(
        () => archive({
          'sources': {'fallback': null},
        }),
        throwsFormatException,
      );
      expect(archive({'sources': {}}).data['sources']!['fallback'], true);
    },
  );

  test(
    'explicit null source protection is rejected while absent uses defaults',
    () {
      expect(
        () => archive({
          'sources': {'protection': null},
        }),
        throwsFormatException,
      );
      expect(archive({'sources': {}}).data['sources']!['protection'], {
        'mode': 'off',
        'interval': 15,
      });
    },
  );

  test(
    'archive metadata always produces a filename portable to cloud and disk',
    () {
      BackupArchive create(String id, String deviceId) => BackupArchive.create(
        id: id,
        deviceId: deviceId,
        createdAt: DateTime.utc(2026, 11, 1),
        deviceName: 'phone',
        appVersion: '2',
        data: {},
      );
      final valid = create('a' * 64, 'd' * 64);
      expect(utf8.encode(valid.fileName).length, lessThanOrEqualTo(240));
      expect(BackupArchive.decode(valid.encode()).fileName, valid.fileName);
      expect(create('a' * 128, 'd' * 128).fileName, valid.fileName);
    },
  );

  test('long Unicode device names retain metadata with a bounded readable filename', () {
    final root = _document(archive({}).encode());
    root['deviceName'] = '手机' * 60;
    final decoded = BackupArchive.decode(_zipDocument(root));
    expect(decoded.deviceName, '手机' * 60);
    expect(decoded.fileName, startsWith('手机'));
    expect(utf8.encode(decoded.fileName).length, lessThanOrEqualTo(240));
  });

  test(
    'explicit null collections cannot masquerade as empty restore groups',
    () {
      expect(
        () => archive({
          'favorites': {'items': null},
        }),
        throwsFormatException,
      );
      expect(
        () => archive({
          'favorites': {'categories': null},
        }),
        throwsFormatException,
      );
      expect(
        () => archive({
          'sources': {'custom': null},
        }),
        throwsFormatException,
      );
      expect(
        () => archive({
          'sources': {'order': null},
        }),
        throwsFormatException,
      );
    },
  );

  test('roundtrip preserves full favorite metadata and immutable records', () {
    final input = <String, Map<String, Object?>>{
      'favorites': {
        'items': [favorite('12345')],
        'categories': ['分类'],
        'sort': 'newest',
      },
    };
    final original = archive(input);
    input['favorites']!['sort'] = 'oldest';
    final restored = BackupArchive.decode(original.encode());
    expect(restored.data['favorites']!['sort'], 'newest');
    expect(
      (restored.data['favorites']!['items'] as List).single,
      favorite('12345'),
    );
    expect(restored.id, 'archive-1');
    expect(restored.deviceName, '测试手机');
    expect(restored.digest, original.digest);
    expect(restored.fileName, '测试手机_2026-11-01_12-13-14.015Z.zip');
    expect(
      () => restored.data['favorites']!['sort'] = 'title',
      throwsUnsupportedError,
    );
    expect(
      () => (restored.data['favorites']!['items'] as List).clear(),
      throwsUnsupportedError,
    );
  });
  test('device filenames escape path characters and keep subsecond backups distinct', () {
    BackupArchive value(int micros) => BackupArchive.create(
      id: 'id',
      deviceId: 'device-id',
      deviceName: '../Pixel:11/Pro%?',
      createdAt: DateTime.utc(2026, 11, 2, 11, 49, 35, 0, micros),
      appVersion: 'test',
      data: {},
    );
    expect(value(1).fileName, isNot(contains(RegExp(r'[<>:"/\\|?*%]'))));
    expect(value(1).fileName, contains('Pixel'));
    expect(value(1).fileName, isNot(value(2).fileName));
    expect(value(1).fileName, isNot(contains('device-id')));
  });

  test('only ordinary settings and update preferences enter archives', () {
    final value = archive({
      'settings': {
        'themeMode': 'dark',
        'autoClipboard': false,
        'privacyMode': true,
        'privacyPasswordHash': 'secret',
        'password': 'secret',
        'deviceId': 'secret',
        'webdav': {'password': 'secret'},
      },
      'updates': {
        'channel': 'beta',
        'autoCheck': false,
        'showUpdatePrompt': false,
        'lastAutomaticCheckAt': '2026-11-01',
        'downloadId': 42,
      },
    });
    expect(value.data['settings']!.keys, isNot(contains('privacyMode')));
    expect(value.data['settings']!['themeMode'], 'dark');
    expect(value.data['settings']!['autoClipboard'], false);
    expect(jsonEncode(_document(value.encode())), isNot(contains('secret')));
    expect(value.data['updates'], {
      'channel': 'beta',
      'autoCheck': false,
      'showUpdatePrompt': false,
    });
    expect(() => archive({'downloads': {}}), throwsFormatException);
  });

  test(
    'canonical payload digest ignores map order but protects list order',
    () {
      final a = archive({
        'settings': {'themeMode': 'light', 'autoClipboard': false},
      });
      final b = archive({
        'settings': {'autoClipboard': false, 'themeMode': 'light'},
      });
      expect(a.digest, b.digest);
      final root = _document(a.encode());
      expect(root['format'], 'xdownloader.backup');
      expect(root['schemaVersion'], 2);
      expect(root['payloadSha256'], a.digest);
      final expected = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'settings': {
                  'autoClipboard': false,
                  'coverCacheLimitMb': 100,
                  'fileNameTemplate': '{author}_{postId}_v{index}_{resolution}',
                  'handedness': 'right',
                  'playfulAvatar': false,
                  'seedColor': 0xFF4F6F52,
                  'themeMode': 'light',
                  'useDynamicColor': false,
                  'useOriginalFileName': false,
                },
              }),
            ),
          )
          .toString();
      // Independent checksum input is intentionally hand ordered.
      expect(a.digest, expected);
    },
  );

  test('rejects corruption unsupported versions invalid UTF8 and limits', () {
    final bytes = archive({
      'favorites': {'items': [], 'categories': []},
    }).encode();
    final root = _document(bytes);
    root['schemaVersion'] = 99;
    expect(
      () => BackupArchive.decode(_zipDocument(root)),
      throwsFormatException,
    );
    root['schemaVersion'] = 2;
    (root['data'] as Map)['favorites'] = {
      'items': [favorite('12345')],
    };
    expect(
      () => BackupArchive.decode(_zipDocument(root)),
      throwsFormatException,
    );
    expect(() => BackupArchive.decode([0xff]), throwsFormatException);
    expect(
      () => BackupArchive.decode(List.filled(16 * 1024 * 1024 + 1, 32)),
      throwsFormatException,
    );
    expect(
      () => archive({
        'favorites': {
          'items': [favorite('12345'), favorite('12345')],
        },
      }),
      throwsFormatException,
    );
    expect(
      () => archive({
        'settings': {'coverCacheLimitMb': -1},
      }),
      throwsFormatException,
    );
    expect(
      () => archive({
        'sources': {
          'custom': [
            {
              'id': 'c1',
              'name': 'bad',
              'kind': 'scrape',
              'endpoint': 'file:///secret',
            },
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects excessive nesting before decoding and unsafe metadata', () {
    final nested = '${'[' * 80}0${']' * 80}';
    expect(() => BackupArchive.decode(_zipText(nested)), throwsFormatException);
    expect(
      () => BackupArchive.create(
        id: '../escape',
        createdAt: DateTime.utc(2026),
        deviceId: 'device',
        deviceName: 'phone',
        appVersion: '2',
        data: {},
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects explicit null portable preferences rather than restoring defaults',
    () {
      expect(
        () => archive({
          'settings': {'coverCacheLimitMb': null},
        }),
        throwsFormatException,
      );
      expect(
        () => archive({
          'updates': {'channel': null},
        }),
        throwsFormatException,
      );
      expect(
        () => archive({
          'updates': {'autoCheck': null},
        }),
        throwsFormatException,
      );
    },
  );
}

Map<String, dynamic> _document(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final manifest = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content)) as Map,
  );
  return {
    ...manifest,
    'data': {
      for (final section in manifest['sections'] as List)
        section: jsonDecode(
          utf8.decode(zip.findFile('$section.json')!.content),
        ),
    },
  };
}

List<int> _zipText(String text) {
  final bytes = utf8.encode(text);
  return ZipEncoder().encode(
    Archive()..add(ArchiveFile('manifest.json', bytes.length, bytes)),
  );
}

List<int> _zipDocument(Map<String, dynamic> document) {
  final archive = Archive();
  final metadata = <String, Object?>{};
  for (final entry in (document['data'] as Map).entries) {
    final bytes = utf8.encode(jsonEncode(entry.value));
    archive.add(ArchiveFile('${entry.key}.json', bytes.length, bytes));
    metadata[entry.key] = {
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    };
  }
  final manifest = {...document, 'documents': metadata}..remove('data');
  final bytes = utf8.encode(jsonEncode(manifest));
  archive.add(ArchiveFile('manifest.json', bytes.length, bytes));
  return ZipEncoder().encode(archive);
}

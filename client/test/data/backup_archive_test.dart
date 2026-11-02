import 'dart:convert';

import 'package:crypto/crypto.dart';
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
      expect(() => create('a' * 128, 'd' * 128), throwsFormatException);
    },
  );

  test(
    'decode rejects metadata whose derived filename exceeds cloud limit',
    () {
      final root =
          jsonDecode(utf8.decode(archive({}).encode())) as Map<String, dynamic>;
      root['archiveId'] = 'a' * 128;
      root['deviceId'] = 'd' * 128;
      expect(
        () => BackupArchive.decode(utf8.encode(jsonEncode(root))),
        throwsFormatException,
      );
    },
  );

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
    expect(
      restored.fileName,
      matches(r'^xdl_.*_device-1_archive-1\.xdlbackup\.json$'),
    );
    expect(
      () => restored.data['favorites']!['sort'] = 'title',
      throwsUnsupportedError,
    );
    expect(
      () => (restored.data['favorites']!['items'] as List).clear(),
      throwsUnsupportedError,
    );
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
    expect(utf8.decode(value.encode()), isNot(contains('secret')));
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
      final root = jsonDecode(utf8.decode(a.encode())) as Map<String, dynamic>;
      expect(root['format'], 'xdownloader.backup');
      expect(root['schemaVersion'], 1);
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
    final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    root['schemaVersion'] = 2;
    expect(
      () => BackupArchive.decode(utf8.encode(jsonEncode(root))),
      throwsFormatException,
    );
    root['schemaVersion'] = 1;
    (root['data'] as Map)['favorites'] = {
      'items': [favorite('12345')],
    };
    expect(
      () => BackupArchive.decode(utf8.encode(jsonEncode(root))),
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
    expect(
      () => BackupArchive.decode(utf8.encode(nested)),
      throwsFormatException,
    );
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

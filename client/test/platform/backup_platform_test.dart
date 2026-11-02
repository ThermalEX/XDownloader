import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/platform/backup_platform.dart';

void main() {
  test('credentials use isolated native methods and exact arguments', () async {
    final calls = <(String, Map<String, Object?>)>[];
    final platform = BackupPlatform(
      call: (method, arguments) async {
        calls.add((method, arguments));
        return method == 'backupReadPassword' ? 'application password' : null;
      },
    );

    expect(await platform.readPassword(), 'application password');
    await platform.writePassword('replacement');
    await platform.writePassword('');

    expect(calls.map((call) => call.$1), [
      'backupReadPassword',
      'backupWritePassword',
      'backupWritePassword',
    ]);
    expect(calls[0].$2, isEmpty);
    expect(calls[1].$2, {'password': 'replacement'});
    expect(calls[2].$2, {'password': ''});
  });

  test(
    'cancel reaches native pending document operations without arguments',
    () async {
      final platform = BackupPlatform(
        call: (method, arguments) async {
          expect(method, 'backupCancel');
          expect(arguments, isEmpty);
          return null;
        },
      );
      await platform.cancel();
    },
  );

  test(
    'immutable credential slots retain the selected account password',
    () async {
      final stored = <String, String>{};
      final platform = BackupPlatform(
        call: (method, arguments) async {
          final key = arguments['key'] as String;
          if (method == 'backupWritePassword') {
            expect(arguments.keys, unorderedEquals(['key', 'password']));
            stored[key] = arguments['password'] as String;
            return null;
          }
          expect(method, 'backupReadPassword');
          expect(arguments.keys, ['key']);
          return stored[key] ?? '';
        },
      );
      await platform.writePassword('first account', key: 'account_A');
      await platform.writePassword('second account', key: 'account_B');
      expect(await platform.readPassword(key: 'account_A'), 'first account');
      expect(await platform.readPassword(key: 'account_B'), 'second account');
    },
  );

  test('invalid credential slots are rejected before native access', () async {
    var calls = 0;
    final platform = BackupPlatform(
      call: (_, _) async {
        calls++;
        return '';
      },
    );
    for (final key in ['', '../account', 'account:secret', 'a' * 129]) {
      await expectLater(platform.readPassword(key: key), throwsArgumentError);
      await expectLater(
        platform.writePassword('secret', key: key),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test('import preserves bytes and cancellation is a normal result', () async {
    Object? reply = Uint8List.fromList([0, 128, 255]);
    final platform = BackupPlatform(
      call: (method, arguments) async {
        expect(method, 'backupImport');
        expect(arguments, isEmpty);
        return reply;
      },
    );

    expect(await platform.importFile(), [0, 128, 255]);
    reply = null;
    expect(await platform.importFile(), isNull);
  });

  test('export sends a codec byte array and preserves cancellation', () async {
    var accepted = true;
    final platform = BackupPlatform(
      call: (method, arguments) async {
        expect(method, 'backupExport');
        expect(arguments['name'], 'archive.zip');
        expect(arguments['bytes'], isA<Uint8List>());
        expect(arguments['bytes'], [0, 128, 255]);
        return accepted;
      },
    );

    expect(await platform.exportFile('archive.zip', [0, 128, 255]), isTrue);
    accepted = false;
    expect(await platform.exportFile('archive.zip', [0, 128, 255]), isFalse);
  });

  test(
    'malformed native replies are rejected without echoing contents',
    () async {
      final platform = BackupPlatform(call: (_, _) async => 'private reply');
      await expectLater(platform.importFile(), throwsFormatException);
      await expectLater(
        platform.exportFile('backup.json', []),
        throwsFormatException,
      );
      final badPassword = BackupPlatform(call: (_, _) async => 12);
      await expectLater(badPassword.readPassword(), throwsFormatException);
    },
  );

  test(
    'unsafe names and invalid bytes never launch a document picker',
    () async {
      var calls = 0;
      final platform = BackupPlatform(
        call: (_, _) async {
          calls++;
          return true;
        },
      );
      for (final name in [
        '',
        '.',
        '..',
        '../backup.json',
        'a/b',
        r'a\b',
        'a\u0000b',
        'a\nb',
      ]) {
        await expectLater(platform.exportFile(name, []), throwsArgumentError);
      }
      await expectLater(
        platform.exportFile('backup.json', [-1]),
        throwsArgumentError,
      );
      await expectLater(
        platform.exportFile('backup.json', [256]),
        throwsArgumentError,
      );
      expect(calls, 0);
    },
  );

  test('archive byte limit applies to both document directions', () async {
    final oversized = Uint8List(16 * 1024 * 1024 + 1);
    var calls = 0;
    final platform = BackupPlatform(
      call: (_, _) async {
        calls++;
        return oversized;
      },
    );
    await expectLater(
      platform.exportFile('backup.json', oversized),
      throwsArgumentError,
    );
    expect(calls, 0);
    await expectLater(platform.importFile(), throwsFormatException);
    expect(calls, 1);
  });

  test(
    'native failures remain failures rather than cancelled documents',
    () async {
      final platform = BackupPlatform(
        call: (_, _) async {
          throw PlatformException(
            code: 'backup',
            message: 'Document unavailable',
          );
        },
      );
      await expectLater(
        platform.importFile(),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        platform.exportFile('backup.json', []),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}

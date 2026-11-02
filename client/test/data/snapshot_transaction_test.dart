import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';

void main() {
  late Directory directory;
  late SnapshotStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xdl-transaction-');
    store = SnapshotStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'batch commits all validated groups and repositories share a gate',
    () async {
      await store.writeBatch({
        'settings': {'autoClipboard': false},
        'sources': {'current': 'fx'},
      });
      final settings = SettingsRepository(store);
      final sources = SourceRepository(store);
      addTearDown(settings.dispose);
      addTearDown(sources.dispose);
      await settings.initialize();
      await sources.initialize();
      expect(settings.value.autoClipboard, false);
      expect(sources.currentId, 'fx');
      final operation = store.mutations.run(() async {
        await store.writeBatch({
          'settings': {'autoClipboard': true},
        });
        await settings.reloadFromStore();
      });
      final edit = settings.edit((s) => s.copyWith(playfulAvatar: true));
      await operation;
      await edit;
      expect(settings.value.autoClipboard, true);
      expect(settings.value.playfulAvatar, true);
    },
  );

  test('invalid group rejects whole batch before any write', () async {
    await store.write('settings', {'autoClipboard': true});
    await expectLater(
      store.writeBatch({
        'settings': {'autoClipboard': false},
        'sources': {'custom': 'invalid'},
      }),
      throwsA(isA<Exception>()),
    );
    expect((await store.read('settings'))['autoClipboard'], true);
  });

  test('cancellation before commit rolls all groups back', () async {
    await store.write('settings', {'autoClipboard': true});
    var checks = 0;
    await expectLater(
      store.writeBatch({
        'settings': {'autoClipboard': false},
        'sources': {'current': 'fx'},
      }, canCommit: () => ++checks < 3),
      throwsA(isA<Exception>()),
    );
    expect((await store.read('settings'))['autoClipboard'], true);
    expect(await store.read('sources'), isEmpty);
    await store.write('settings', {'autoClipboard': false});
    expect((await store.read('settings'))['autoClipboard'], false);
  });

  for (final committed in [false, true]) {
    test(
      'restart resolves ${committed ? 'committed' : 'prepared'} journal consistently',
      () async {
        await store.write('settings', {'autoClipboard': false});
        await File('${directory.path}/restore_transaction.json').writeAsString(
          jsonEncode({
            'version': 1,
            'committed': committed,
            'before': {
              'settings': {'autoClipboard': true},
              'sources': null,
            },
            'after': {
              'settings': {'autoClipboard': false},
              'sources': {'current': 'fx'},
            },
          }),
        );
        final reopened = SnapshotStore(directory);
        await reopened.recover();
        expect((await reopened.read('settings'))['autoClipboard'], !committed);
        expect(
          (await reopened.read('sources'))['current'],
          committed ? 'fx' : null,
        );
        expect(
          await File('${directory.path}/restore_transaction.json').exists(),
          false,
        );
      },
    );
  }

  test(
    'corrupt journal blocks writes and remains available for recovery',
    () async {
      final journal = File('${directory.path}/restore_transaction.json');
      await journal.writeAsString('{broken');
      await expectLater(store.recover(), throwsA(isA<Exception>()));
      await expectLater(store.write('settings', {}), throwsA(isA<Exception>()));
      expect(await journal.readAsString(), '{broken');
    },
  );
  test(
    'durable commit marker rolls forward without replacing prepared journal',
    () async {
      final journal = jsonEncode({
        'version': 1,
        'committed': false,
        'before': {
          'settings': {'autoClipboard': true},
        },
        'after': {
          'settings': {'autoClipboard': false},
        },
      });
      await File('${directory.path}/restore_transaction.json')
          .writeAsString(journal);
      await File('${directory.path}/restore_transaction.commit')
          .writeAsString(sha256.convert(utf8.encode(journal)).toString());
      await store.recover();
      expect((await store.read('settings'))['autoClipboard'], false);
    },
  );
  for (final stage in [
    'restore_transaction.json.tmp',
    'sources.json.tmp',
    'restore_transaction.commit.tmp',
  ]) {
    test('IO failure at $stage never leaves partial restored data', () async {
      await store.write('settings', {'autoClipboard': true});
      await Directory('${directory.path}/$stage').create();
      await expectLater(
        store.writeBatch({
          'settings': {'autoClipboard': false},
          'sources': {'current': 'fx'},
        }),
        throwsA(isA<Exception>()),
      );
      await Directory('${directory.path}/$stage').delete();
      await store.recover();
      expect((await store.read('settings'))['autoClipboard'], true);
      expect(await store.read('sources'), isEmpty);
    });
  }
  test(
    'batch refuses to treat corrupt originals as missing before state',
    () async {
      final file = File('${directory.path}/settings.json');
      await file.writeAsString('{broken');
      await expectLater(
        store.writeBatch({
          'settings': {'autoClipboard': true},
        }),
        throwsA(isA<Exception>()),
      );
      expect(await file.readAsString(), '{broken');
    },
  );
}

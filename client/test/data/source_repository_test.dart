import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

void main() {
  late Directory temp;
  late SnapshotStore store;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-sources-');
    store = SnapshotStore(temp);
  });
  tearDown(() async => temp.delete(recursive: true));
  const custom = ParseSource(
    'custom',
    '自定义',
    'https://source.test/?url={urlenc}',
    SourceKind.scrape,
    'POST',
    'url={urlenc}',
    false,
  );
  test(
    'source edits and selection survive restart with builtins intact',
    () async {
      final repo = SourceRepository(store);
      await repo.initialize();
      await repo.addCustom(custom);
      await repo.select('custom');
      await repo.setFallback(false);
      final restored = SourceRepository(store);
      await restored.initialize();
      expect(restored.list.length, 8);
      expect(restored.parseOrder.first.id, 'custom');
      expect(restored.autoFallback, isFalse);
      await restored.remove('custom');
      expect(restored.currentId, 'xdl');
      await expectLater(restored.remove('fx'), throwsA(isA<AppFailure>()));
    },
  );
  test(
    'invalid sources and failed persistence do not mutate visible state',
    () async {
      final repo = SourceRepository(store);
      await repo.initialize();
      await expectLater(
        repo.addCustom(
          const ParseSource(
            'c',
            'Bad',
            'file:///tmp/test',
            SourceKind.scrape,
            'GET',
            '',
            false,
          ),
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.list.length, 7);
      await Directory('${temp.path}/sources.json.tmp').create();
      await expectLater(repo.select('fx'), throwsA(isA<AppFailure>()));
      expect(repo.currentId, 'xdl');
    },
  );
  test('theme and clipboard settings are durable', () async {
    final settings = SettingsRepository(store);
    await settings.initialize();
    await settings.update(
      const AppSettings(
        themeMode: AppThemeMode.dark,
        seedColor: 0xFF334488,
        useDynamicColor: true,
        autoClipboard: false,
      ),
    );
    final restored = SettingsRepository(store);
    await restored.initialize();
    expect(restored.value.themeMode, AppThemeMode.dark);
    expect(restored.value.seedColor, 0xFF334488);
    expect(restored.value.autoClipboard, isFalse);
    expect(restored.value.useDynamicColor, isTrue);
  });
  test('concurrent setting transforms preserve both changes', () async {
    final settings = SettingsRepository(store);
    await settings.initialize();
    await Future.wait([
      settings.edit(
        (current) => current.copyWith(themeMode: AppThemeMode.dark),
      ),
      settings.edit((current) => current.copyWith(autoClipboard: false)),
    ]);
    final restored = SettingsRepository(store);
    await restored.initialize();
    expect(restored.value.themeMode, AppThemeMode.dark);
    expect(restored.value.autoClipboard, isFalse);
  });
}

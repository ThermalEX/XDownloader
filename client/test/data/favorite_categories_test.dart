import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';
import 'package:xdownloader/data/storage/snapshot_schema.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/app_fixture.dart';

class CategoryStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    if (fail) throw const AppFailure(FailureKind.storage, 'write failed');
    await super.write(key, data);
  }
}

void main() {
  test('invalid category registry recovers the last complete snapshot including empty categories', () async {
    final dir = await Directory.systemTemp.createTemp('xdl-categories-');
    try {
      final store = SnapshotStore(dir);
      final repo = FavoriteRepository(store);
      await repo.initialize();
      await repo.addCategory('空分类');
      await repo.setSort(FavoriteSort.title);
      await repo.setSort(FavoriteSort.newest);
      final file = File('${dir.path}/favorites.json');
      final document = jsonDecode(await file.readAsString()) as Map;
      (document['data'] as Map)['categories'] = ['空分类', 3];
      await file.writeAsString(jsonEncode(document));
      final recovered = FavoriteRepository(store);
      await recovered.initialize();
      expect(recovered.categories, ['空分类']);
      expect(recovered.sort, FavoriteSort.title);
      expect(recovered.items, isEmpty);
      repo.dispose();
      recovered.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('empty categories persist alongside legacy assignments after all favorites are removed', () async {
    final store = CategoryStore();
    final repo = FavoriteRepository(store);
    await repo.initialize();
    await repo.add('https://x.com/a/status/123456', title: '原名');
    await repo.update('123456', title: '原名', category: '音乐');
    final legacy = await store.read('favorites')
      ..remove('categories');
    await store.write('favorites', legacy);
    final migrated = FavoriteRepository(store);
    await migrated.initialize();
    expect(migrated.categories, ['音乐']);
    expect(await migrated.addCategory('  旅行  '), true);
    expect(await migrated.addCategory('旅行'), false);
    await migrated.setSort(FavoriteSort.title);
    await migrated.remove('123456');
    final restored = FavoriteRepository(store);
    await restored.initialize();
    expect(restored.items, isEmpty);
    expect(restored.categories, ['音乐', '旅行']);
    expect(restored.sort, FavoriteSort.title);
    repo.dispose();
    migrated.dispose();
    restored.dispose();
  });
  test('category writes validate, serialize and do not create phantom state on failure', () async {
    final store = CategoryStore();
    final repo = FavoriteRepository(store);
    await repo.initialize();
    expect(await Future.wait([repo.addCategory('A'), repo.addCategory('A')]), [
      true,
      false,
    ]);
    await expectLater(repo.addCategory('  '), throwsA(isA<AppFailure>()));
    await expectLater(repo.addCategory('长' * 41), throwsA(isA<AppFailure>()));
    store.fail = true;
    await expectLater(repo.addCategory('B'), throwsA(isA<AppFailure>()));
    expect(repo.categories, ['A']);
    expect(
      SnapshotSchema.accepts('favorites', {
        'categories': ['A', 1],
      }),
      false,
    );
    expect(
      SnapshotSchema.accepts('favorites', {
        'categories': ['A', 'A'],
      }),
      false,
    );
    expect(
      SnapshotSchema.accepts('favorites', {
        'categories': [''],
      }),
      false,
    );
    repo.dispose();
  });
}

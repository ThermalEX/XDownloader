import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/app_fixture.dart';

class FailingFavoriteStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    if (fail) throw const AppFailure(FailureKind.storage, 'cannot save');
    await super.write(key, data);
  }
}

void main() {
  test(
    'default order and undo retain neighbors metadata and concurrent additions',
    () async {
      final store = FailingFavoriteStore();
      final repo = FavoriteRepository(store);
      await repo.initialize();
      expect(repo.sort, FavoriteSort.defaultOrder);
      await repo.add('https://x.com/a/status/123456', title: 'One');
      await repo.add('https://x.com/b/status/234567', title: 'Two');
      await repo.update('123456', title: 'Edited', category: '音乐');
      final original = repo.items.last;
      final removed = (await repo.removeForUndo('123456'))!;
      await repo.add('https://x.com/c/status/345678', title: 'Three');
      store.fail = true;
      await expectLater(repo.restore(removed), throwsA(isA<AppFailure>()));
      expect(repo.items.map((f) => f.postId), ['345678', '234567']);
      store.fail = false;
      await repo.restore(removed);
      expect(repo.items.map((f) => f.postId), ['345678', '234567', '123456']);
      expect(repo.items.last.toJson(), original.toJson());
      final reloaded = FavoriteRepository(store);
      await reloaded.initialize();
      expect(reloaded.sort, FavoriteSort.defaultOrder);
      expect(reloaded.items.last.toJson(), original.toJson());
      final duplicate = (await repo.removeForUndo('123456'))!;
      await repo.add('https://x.com/a/status/123456', title: 'New entry');
      await repo.restore(duplicate);
      expect(
        repo.items.where((f) => f.postId == '123456').single.title,
        'New entry',
      );
      repo.dispose();
      reloaded.dispose();
    },
  );
  test(
    'durable favorite sort and category recover after invalid sort snapshot',
    () async {
      final dir = await Directory.systemTemp.createTemp('xdl-favorite-sort-');
      try {
        final store = SnapshotStore(dir);
        final repo = FavoriteRepository(store);
        await repo.initialize();
        await repo.add('https://x.com/a/status/123456', title: '名称');
        await repo.update('123456', title: '名称', category: '音乐');
        await repo.setSort(FavoriteSort.title);
        final restored = FavoriteRepository(store);
        await restored.initialize();
        expect(restored.sort, FavoriteSort.title);
        expect(restored.items.single.category, '音乐');
        await File('${dir.path}/favorites.json')
            .writeAsString('{"version":1,"data":{"sort":"broken","items":[]}}');
        final recovered = FavoriteRepository(store);
        await recovered.initialize();
        expect(recovered.items.single.category, '音乐');
        repo.dispose();
        restored.dispose();
        recovered.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'old favorites migrate and edits sorting categories survive reload',
    () async {
      final store = MemorySnapshotStore();
      await store.write('favorites', {
        'items': [
          {
            'postId': '123456',
            'url': 'https://x.com/a/status/123456',
            'title': 'Zulu',
            'createdAt': '2026-10-01T00:00:00Z',
          },
          {
            'postId': '234567',
            'url': 'https://x.com/b/status/234567',
            'title': 'Alpha',
            'createdAt': '2026-10-02T00:00:00Z',
          },
        ],
      });
      final repo = FavoriteRepository(store);
      await repo.initialize();
      expect(repo.items.every((f) => f.category.isEmpty), isTrue);
      await repo.update('123456', title: 'Beta', category: ' 音乐 ');
      await repo.setSort(FavoriteSort.title);
      expect(repo.items.map((f) => f.title), ['Alpha', 'Beta']);
      await Future.wait([
        repo.setSort(FavoriteSort.oldest),
        repo.update('234567', title: '新名称', category: '电影'),
      ]);
      final restored = FavoriteRepository(store);
      await restored.initialize();
      expect(restored.sort, FavoriteSort.oldest);
      expect(restored.items.map((f) => f.postId), ['123456', '234567']);
      expect(restored.categories, ['音乐', '电影']);
      expect(restored.items.first.category, '音乐');
      await restored.add('https://x.com/a/status/123456', title: '自动解析标题');
      expect(restored.items.first.title, 'Beta');
      repo.dispose();
      restored.dispose();
    },
  );
  test(
    'failed favorite edits leave title category and sorting intact',
    () async {
      final store = FailingFavoriteStore();
      final repo = FavoriteRepository(store);
      await repo.initialize();
      await repo.add('https://x.com/a/status/123456', title: '原名');
      store.fail = true;
      await expectLater(
        repo.update('123456', title: '新名', category: '分类'),
        throwsA(isA<AppFailure>()),
      );
      await expectLater(
        repo.setSort(FavoriteSort.title),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.sort, FavoriteSort.defaultOrder);
      expect(repo.items.single.title, '原名');
      expect(repo.categories, isEmpty);
      repo.dispose();
    },
  );
  test('favorites canonicalize share text and deduplicate Twitter and X by post id', () async {
    final store = MemorySnapshotStore();
    final repo = FavoriteRepository(store);
    await repo.initialize();
    expect(
      await repo.add('分享 https://twitter.com/author/status/123456?s=20'),
      isTrue,
    );
    expect(
      await repo.add('https://x.com/another/status/123456', title: '示例'),
      isFalse,
    );
    expect(repo.items, hasLength(1));
    expect(repo.items.single.url.host, 'x.com');
    expect(repo.items.single.title, '示例');
    final restored = FavoriteRepository(store);
    await restored.initialize();
    expect(restored.items.single.postId, '123456');
    await restored.remove('123456');
    expect(restored.items, isEmpty);
    repo.dispose();
    restored.dispose();
  });
  test(
    'invalid, failed and concurrent writes preserve durable favorites',
    () async {
      final store = FailingFavoriteStore();
      final repo = FavoriteRepository(store);
      await repo.initialize();
      await expectLater(
        repo.add('https://evil.test/a'),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.items, isEmpty);
      store.fail = true;
      await expectLater(
        repo.add('https://x.com/a/status/123456'),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.items, isEmpty);
      store.fail = false;
      await Future.wait([
        repo.add('https://x.com/a/status/123456'),
        repo.add('https://twitter.com/a/status/123456'),
        repo.add('https://x.com/b/status/234567'),
      ]);
      expect(repo.items.map((f) => f.postId), ['234567', '123456']);
      store.fail = true;
      await expectLater(repo.remove('123456'), throwsA(isA<AppFailure>()));
      expect(repo.items, hasLength(2));
      repo.dispose();
    },
  );
  test(
    'favorites recover valid backup when current payload is damaged',
    () async {
      final directory = await Directory.systemTemp.createTemp('xdl-favorites-');
      try {
        final store = SnapshotStore(directory);
        final repo = FavoriteRepository(store);
        await repo.initialize();
        await repo.add('https://x.com/a/status/123456');
        await repo.add('https://x.com/b/status/234567');
        await File('${directory.path}/favorites.json')
            .writeAsString('{"version":1,"data":{"items":[{"postId":"bad"}]}}');
        final restored = FavoriteRepository(store);
        await restored.initialize();
        expect(restored.items.single.postId, '123456');
        repo.dispose();
        restored.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

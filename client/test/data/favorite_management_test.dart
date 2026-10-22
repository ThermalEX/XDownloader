import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';

import '../support/app_fixture.dart';

class ManagementStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    if (fail) throw const AppFailure(FailureKind.storage, 'write failed');
    await super.write(key, data);
  }
}

void main() {
  test('single undo never revives a category renamed or deleted while the item was removed', () async {
    for (final rename in [false, true]) {
      final repo = FavoriteRepository(ManagementStore());
      await repo.initialize();
      await repo.add('https://x.com/a/status/123456', title: '原名称');
      await repo.update('123456', title: '原名称', category: 'A');
      final removed = (await repo.removeForUndo('123456'))!;
      if (rename) {
        await repo.renameCategory('A', 'B');
      } else {
        await repo.deleteCategory('A');
      }
      await repo.restore(removed);
      expect(repo.categories, rename ? ['B'] : isEmpty);
      expect(repo.items.single.category, '');
      expect(repo.items.single.title, '原名称');
      repo.dispose();
    }
  });
  test(
    'category rename/delete update all members atomically and preserve links',
    () async {
      final store = ManagementStore();
      final repo = FavoriteRepository(store);
      await repo.initialize();
      await repo.add('https://x.com/a/status/123456', title: 'One');
      await repo.update('123456', title: 'One', category: '旧分类');
      final before = repo.items.single;
      await repo.addCategory('空分类');
      await repo.renameCategory('旧分类', '新分类');
      expect(repo.categories, ['新分类', '空分类']);
      expect(repo.items.single.category, '新分类');
      await expectLater(
        repo.renameCategory('新分类', '空分类'),
        throwsA(isA<AppFailure>()),
      );
      store.fail = true;
      await expectLater(repo.deleteCategory('新分类'), throwsA(isA<AppFailure>()));
      expect(repo.items.single.category, '新分类');
      store.fail = false;
      await repo.deleteCategory('新分类');
      expect(repo.categories, ['空分类']);
      expect(repo.items.single.category, '');
      expect(repo.items.single.url, before.url);
      expect(repo.items.single.createdAt, before.createdAt);
      final restored = FavoriteRepository(store);
      await restored.initialize();
      expect(restored.categories, ['空分类']);
      expect(restored.items.single.category, '');
      repo.dispose();
      restored.dispose();
    },
  );
  test('batch removal and undo preserve positions and concurrent additions with one durable change', () async {
    final store = ManagementStore();
    final repo = FavoriteRepository(store);
    await repo.initialize();
    for (final id in ['123456', '234567', '345678']) {
      await repo.add('https://x.com/a/status/$id', title: id);
    }
    final original = repo.items.map((f) => f.toJson()).toList();
    store.fail = true;
    await expectLater(
      repo.removeManyForUndo({'123456', '234567'}),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.items, hasLength(3));
    store.fail = false;
    final removed = await repo.removeManyForUndo({'123456', '234567'});
    expect(repo.items.map((f) => f.postId), ['345678']);
    await repo.add('https://x.com/a/status/456789', title: 'New');
    await repo.restoreMany(removed);
    expect(repo.items.first.postId, '456789');
    expect(repo.items.skip(1).map((f) => f.toJson()).toList(), original);
    repo.dispose();
  });
}

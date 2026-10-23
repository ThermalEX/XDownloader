import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/favorite_link.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';
import 'package:xdownloader/features/home/home_controller.dart';

import '../support/app_fixture.dart';

void main() {
  test(
    'stored parsed author survives edits undo and repository reload',
    () async {
      final store = MemorySnapshotStore();
      await store.write('favorites', {
        'items': [
          {
            'postId': '123456',
            'url': 'https://x.com/account/status/123456',
            'title': '标题',
            'author': '解析作者',
            'createdAt': '2026-10-01T00:00:00Z',
          },
        ],
      });
      final repo = FavoriteRepository(store);
      await repo.initialize();
      expect(repo.items.single.toJson()['author'], '解析作者');
      await repo.update('123456', title: '新标题', category: '分类');
      final removed = (await repo.removeForUndo('123456'))!;
      await repo.restore(removed);
      final restored = FavoriteRepository(store);
      await restored.initialize();
      expect(restored.items.single.toJson()['author'], '解析作者');
      repo.dispose();
      restored.dispose();
    },
  );

  test(
    'new favorites normalize author and metadata updates retain renamed title',
    () async {
      final store = MemorySnapshotStore();
      final repo = FavoriteRepository(store);
      await repo.initialize();
      await repo.add(
        'https://x.com/account/status/123456',
        title: '自定名称',
        author: ' 初始作者 ',
      );
      expect(repo.items.single.author, '初始作者');
      await repo.add(
        'https://x.com/account/status/123456',
        title: '原始标题',
        author: '更新作者',
      );
      expect(repo.items.single.author, '更新作者');
      expect(repo.items.single.title, '自定名称');
      await repo.rememberMetadata('123456', author: '  ');
      expect(repo.items.single.author, '更新作者');
      final restored = FavoriteRepository(store);
      await restored.initialize();
      expect(restored.items.single.author, '更新作者');
      repo.dispose();
      restored.dispose();
    },
  );

  test('parsing an existing favorite saves author while privacy blocks metadata changes', () async {
    final fixture = AppFixture();
    await fixture.initialize();
    final home = HomeController(fixture.dependencies);
    try {
      await fixture.favorites.add('https://x.com/account/status/123456');
      await home.parse('https://x.com/account/status/123456');
      await Future<void>.delayed(Duration.zero);
      expect(fixture.favorites.items.single.author, '中文作者');
      await fixture.favorites.add('https://x.com/account/status/234567');
      await fixture.settings.edit((s) => s.copyWith(privacyMode: true));
      await home.parse('https://x.com/account/status/234567');
      await Future<void>.delayed(Duration.zero);
      expect(home.result?.post.postId, '234567');
      expect(fixture.favorites.items.first.author, isNull);
    } finally {
      home.dispose();
      await fixture.close();
    }
  });

  test('favorite author round trips independently of link account', () {
    final item = FavoriteLink.fromJson({
      'postId': '123456',
      'url': 'https://x.com/account/status/123456',
      'title': '标题',
      'author': '作者显示名',
      'createdAt': '2026-10-01T00:00:00Z',
    });
    expect(item.copyWith(title: '重命名').toJson()['author'], '作者显示名');
  });
}

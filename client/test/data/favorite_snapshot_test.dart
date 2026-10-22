import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';

import 'favorite_repository_test.dart' show FailingFavoriteStore;

void main() {
  test(
    'immutable sorted snapshot is reused until a successful mutation',
    () async {
      final store = FailingFavoriteStore();
      final repo = FavoriteRepository(store);
      addTearDown(repo.dispose);
      await repo.initialize();
      await repo.add('https://x.com/a/status/123456', title: 'alpha');
      await repo.add('https://x.com/b/status/234567', title: 'ALPHA');
      await repo.setSort(FavoriteSort.title);
      final snapshot = repo.items;
      expect(identical(snapshot, repo.items), isTrue);
      expect(snapshot.map((f) => f.postId), ['234567', '123456']);
      expect(() => snapshot.clear(), throwsUnsupportedError);
      store.fail = true;
      await expectLater(
        repo.update('123456', title: 'Beta', category: ''),
        throwsA(anything),
      );
      expect(identical(snapshot, repo.items), isTrue);
      store.fail = false;
      await repo.update('123456', title: 'Beta', category: '');
      expect(repo.items.map((f) => f.title), ['ALPHA', 'Beta']);
      expect(snapshot.last.title, 'alpha');
      final removed = (await repo.removeForUndo('234567'))!;
      await repo.restore(removed);
      expect(repo.items.map((f) => f.title), ['ALPHA', 'Beta']);
      await repo.setSort(FavoriteSort.defaultOrder);
      expect(repo.items.map((f) => f.postId), ['234567', '123456']);
    },
  );
}

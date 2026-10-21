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

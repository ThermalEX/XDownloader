import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/favorite_link.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';

import '../support/app_fixture.dart';

void main() {
  test('adding cover metadata never replaces an existing favorite title or category', () async {
    final store = MemorySnapshotStore();
    final repo = FavoriteRepository(store);
    await repo.initialize();
    await repo.add('https://x.com/a/status/123456', title: 'original');
    await repo.update('123456', title: 'renamed', category: 'Music');
    final cover = Uri.parse('https://pbs.twimg.com/a.jpg');
    expect(
      await repo.add(
        'https://x.com/a/status/123456',
        title: 'other',
        coverUrl: cover,
      ),
      isFalse,
    );
    final item = repo.items.single;
    expect(item.title, 'renamed');
    expect(item.category, 'Music');
    expect(item.coverUrl, cover);
    final restored = FavoriteRepository(store);
    await restored.initialize();
    expect(restored.items.single.coverUrl, cover);
    final old = item.toJson()..remove('coverUrl');
    expect(FavoriteLink.fromJson(old).coverUrl, isNull);
    await repo.rememberCover('999999', cover);
    expect(repo.items, hasLength(1));
    repo.dispose();
    restored.dispose();
  });
  test(
    'download retry metadata keeps the cover URL and old records stay valid',
    () {
      final request = DownloadRequest(
        taskId: 'a',
        url: Uri.parse('https://video.twimg.com/a.mp4'),
        displayName: 'a',
        headers: const {},
        mediaIndex: 1,
        coverUrl: Uri.parse('https://pbs.twimg.com/a.jpg'),
      );
      expect(
        DownloadRequest.fromJson(request.withId('b').toJson()).coverUrl,
        request.coverUrl,
      );
      expect(
        DownloadRequest.fromJson(request.toJson()..remove('coverUrl')).coverUrl,
        isNull,
      );
    },
  );
  test('cache size defaults safely and rejects corrupt persisted values', () {
    expect(AppSettings.fromJson({}).coverCacheLimitMb, 100);
    for (final value in [-1, 2049, 1.5, '100']) {
      expect(
        () => AppSettings.fromJson({'coverCacheLimitMb': value}),
        throwsFormatException,
      );
    }
  });
}

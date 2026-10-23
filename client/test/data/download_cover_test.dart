import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/data/repositories/cover_cache_repository.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';

import '../support/app_fixture.dart';

class CoverBackend extends UiDownloadBackend {
  int extractions = 0;
  bool hasThumbnail = true;
  @override
  Future<Uint8List?> thumbnailSavedFile(SavedFile file) async {
    extractions++;
    return hasThumbnail ? Uint8List.fromList([1, 2, 3]) : null;
  }
}

void main() {
  test('secondary video without native cover falls back to remote', () async {
    final root = await Directory.systemTemp.createTemp('xdl-cover-fallback-');
    final settings = SettingsRepository(MemorySnapshotStore());
    await settings.initialize();
    var requests = 0;
    final cache = CoverCacheRepository(
      root: root,
      settings: settings,
      client: MockClient((request) async {
        requests++;
        expect(request.url.toString(), 'https://pbs.twimg.com/cover.jpg');
        return http.Response.bytes(
          [4, 5, 6],
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      }),
    );
    await cache.initialize();
    final backend = CoverBackend()..hasThumbnail = false;
    final repo = DownloadRepository(
      store: MemorySnapshotStore(),
      backend: backend,
      coverCache: cache,
    );
    await repo.initialize();
    try {
      await repo.start(
        DownloadRequest(
          taskId: 'second',
          url: Uri.parse('https://video.twimg.com/a.mp4'),
          displayName: 'a.mp4',
          headers: const {},
          mediaIndex: 2,
          postUrl: Uri.parse('https://x.com/a/status/123456'),
          coverUrl: Uri.parse('https://pbs.twimg.com/cover.jpg'),
        ),
      );
      backend.emit(
        const BackendTaskSnapshot(
          taskId: 'second',
          phase: BackendPhase.transferred,
          bytes: 8,
        ),
      );
      await repo.reconcile();
      expect(
        await repo.favoriteCover('123456').timeout(const Duration(seconds: 1)),
        [4, 5, 6],
      );
      expect(requests, 1);
      expect(await repo.favoriteCover('123456'), [4, 5, 6]);
      expect(backend.extractions, 1);
      expect(requests, 1);
    } finally {
      repo.dispose();
      await backend.close();
      settings.dispose();
      await root.delete(recursive: true);
    }
  });
  for (final mediaIndex in [1, 2]) {
    test(
      'shared cover loads and restart retention for media $mediaIndex',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'xdl-cover-repository-',
        );
        final settings = SettingsRepository(MemorySnapshotStore());
        await settings.initialize();
        final cache = CoverCacheRepository(root: root, settings: settings);
        await cache.initialize();
        final backend = CoverBackend();
        var repo = DownloadRepository(
          store: MemorySnapshotStore(),
          backend: backend,
          coverCache: cache,
        );
        await repo.initialize();
        try {
          await repo.start(
            DownloadRequest(
              taskId: 'second',
              url: Uri.parse('https://video.twimg.com/a.mp4'),
              displayName: 'a.mp4',
              headers: const {},
              mediaIndex: mediaIndex,
              postUrl: Uri.parse('https://x.com/a/status/123456'),
            ),
          );
          backend.emit(
            const BackendTaskSnapshot(
              taskId: 'second',
              phase: BackendPhase.transferred,
              bytes: 8,
            ),
          );
          await repo.reconcile();
          final favorite = repo.favoriteCover('123456');
          final downloaded = repo.thumbnail('second');
          expect(await downloaded, [1, 2, 3]);
          expect(await favorite, [1, 2, 3]);
          expect(backend.extractions, 1);
          await repo.removeRecord('second');
          final store = repo.store;
          repo.dispose();
          final restored = CoverCacheRepository(root: root, settings: settings);
          await restored.initialize();
          repo = DownloadRepository(
            store: store,
            backend: backend,
            coverCache: restored,
          );
          await repo.initialize();
          expect(await repo.favoriteCover('123456'), [1, 2, 3]);
          expect(backend.extractions, 1);
          await restored.clear();
          expect(await repo.favoriteCover('123456'), isNull);
        } finally {
          repo.dispose();
          await backend.close();
          settings.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
}

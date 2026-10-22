import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/download_history.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';

import '../support/app_fixture.dart';

void main() {
  test('source references survive reload and use history only when a stored post link is missing', () async {
    final store = MemorySnapshotStore();
    final backend = UiDownloadBackend();
    final now = DateTime.utc(2026, 10, 22);
    final records = [
      for (final id in ['direct', 'fallback', 'missing', 'failed'])
        DownloadRecord(
          request: DownloadRequest(
            taskId: id,
            // A transfer URL that looks like a post must never be inferred.
            url: Uri.parse('https://x.com/wrong/status/999999'),
            displayName: '$id.MP4',
            headers: const {},
            mediaIndex: 1,
            postUrl: id == 'direct'
                ? Uri.parse('https://twitter.com/right/status/123456?s=20')
                : null,
          ),
          phase: id == 'failed'
              ? DownloadPhase.failed
              : DownloadPhase.completed,
          createdAt: now,
          legacy: true,
        ),
    ];
    await store.write('downloads', {
      'records': records.map((r) => r.toJson()).toList(),
      'historyVersion': 1,
      'history': [
        for (final id in ['direct', 'fallback', 'failed'])
          DownloadHistoryEntry(
            taskId: id,
            displayName: '$id.mp4',
            postUrl: Uri.parse('https://x.com/history/status/234567'),
            createdAt: now,
            finishedAt: now,
            phase: DownloadPhase.completed,
          ).toJson(),
      ],
    });
    final repo = DownloadRepository(store: store, backend: backend);
    try {
      await repo.initialize();
      expect(
        repo.sourceForFavorite('direct')?.url.toString(),
        'https://x.com/right/status/123456',
      );
      expect(
        repo.sourceForFavorite('fallback')?.url.toString(),
        'https://x.com/history/status/234567',
      );
      expect(repo.sourceForFavorite('fallback')?.title, 'fallback');
      expect(repo.sourceForFavorite('missing'), isNull);
      expect(repo.sourceForFavorite('failed'), isNull);
      expect(repo.sourceForFavorite('unknown'), isNull);
      expect(backend.enqueued, isEmpty);
    } finally {
      repo.dispose();
      await backend.close();
    }
  });
}

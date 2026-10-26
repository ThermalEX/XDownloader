import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:http/http.dart' as http;
import 'package:xdownloader/core/models/source.dart';

import '../support/fixture_client.dart';

import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/features/settings/source_health_controller.dart';

import '../support/app_fixture.dart';

void main() {
  test(
    'cooldown expires and source attempt callback follows real outcomes only',
    () async {
      var now = DateTime.utc(2026, 10, 26);
      final repo = SourceRepository(MemorySnapshotStore(), now: () => now);
      await repo.initialize();
      repo.recordAttempt('fx', false);
      expect(repo.parseOrder.map((s) => s.id), isNot(contains('fx')));
      now = now.add(const Duration(minutes: 2));
      expect(repo.parseOrder.map((s) => s.id), contains('fx'));
      final attempts = <String>[];
      var calls = 0;
      final parser = ParseClient(
        onAttempt: (id, success) {
          attempts.add('$id:$success');
        },
        clientFactory: () => FixtureClient((_) {
          calls++;
          return http.Response(
            calls == 1 ? 'offline' : '<a href="https://video.twimg.com/amplify_video/1/vid/320x568/a.mp4">MP4</a>',
            calls == 1 ? 503 : 200,
          );
        }),
      );
      final sources = ['a', 'b']
          .map(
            (id) => ParseSource(
              id,
              id,
              'https://example.test/$id',
              SourceKind.scrape,
              'GET',
              '',
              false,
            ),
          )
          .toList();
      final result = await parser.parse(
        'https://x.com/a/status/123456',
        sources: sources,
        autoFallback: true,
        cancellation: ParseCancellation(),
      );
      expect(result.sourceId, 'b');
      expect(attempts, ['a:false', 'b:true']);
      final cancelled = ParseCancellation()..cancel();
      await expectLater(
        parser.parse(
          'https://x.com/a/status/123456',
          sources: sources,
          autoFallback: true,
          cancellation: cancelled,
        ),
        throwsA(anything),
      );
      expect(attempts, ['a:false', 'b:true']);
      repo.dispose();
    },
  );

  test('source priority survives settings edits and restart without changing selection', () async {
    final store = MemorySnapshotStore();
    final repository = SourceRepository(store);
    await repository.initialize();
    await repository.movePriority('twmate', -1);
    expect(repository.list.last.id, 'twsaver');
    expect(repository.currentId, 'xdl');
    await repository.setFallback(false);
    await repository.select('fx');
    final restored = SourceRepository(store);
    await restored.initialize();
    expect(restored.list.map((s) => s.id), repository.list.map((s) => s.id));
    expect(restored.currentId, 'fx');
    expect(restored.autoFallback, isFalse);
    restored.dispose();
    repository.dispose();
  });
  test('failed backup cooldown exposes later sources but explicit selection stays first', () async {
    final repository = SourceRepository(MemorySnapshotStore());
    await repository.initialize();
    for (final id in ['fx', 'syndication', 'vx', 'twitsave']) {
      repository.recordAttempt(id, false);
    }
    expect(repository.parseOrder.take(5).map((s) => s.id), [
      'xdl',
      'snap',
      'savetwitter',
      'twdown',
      'tweetdl',
    ]);
    await repository.select('fx');
    expect(repository.parseOrder.first.id, 'fx');
    repository.recordAttempt('vx', true);
    expect(repository.parseOrder.map((s) => s.id), contains('vx'));
    repository.dispose();
  });
  test(
    'health distinguishes valid parse from unavailable MP4 transfer',
    () async {
      final parser = FixtureParser();
      parser.verifyResponse = (_, _) async => throw Exception('broken media');
      final health = SourceHealthController(parser);
      final repository = SourceRepository(MemorySnapshotStore());
      await repository.initialize();
      await health.check(repository.list.first);
      expect(parser.mediaChecks, 1);
      expect(health.result('xdl'), contains('可解析'));
      expect(health.result('xdl'), contains('下载验证失败'));
      health.dispose();
      repository.dispose();
    },
  );
  test(
    'health confirms actual video and ignores late checks after disposal',
    () async {
      final parser = FixtureParser();
      final health = SourceHealthController(parser);
      final repo = SourceRepository(MemorySnapshotStore());
      await repo.initialize();
      await health.check(repo.list.first);
      expect(parser.mediaChecks, 1);
      expect(health.result('xdl'), contains('已验证视频'));
      health.dispose();
      repo.dispose();
    },
  );
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';

import '../support/app_fixture.dart';

class FailingSourceStore extends MemorySnapshotStore {
  bool fail = false;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    if (fail) throw const AppFailure(FailureKind.storage, 'cannot save');
    await super.write(key, data);
  }
}

void main() {
  test('source exchange accepts explicit subsets and rejects invalid selection atomically', () async {
    final repo = SourceRepository(MemorySnapshotStore());
    await repo.initialize();
    final first = repo.list.first;
    expect(
      (jsonDecode(repo.exportSources(ids: {first.id}))['sources'] as List),
      hasLength(1),
    );
    expect(() => repo.exportSources(ids: {}), throwsA(isA<AppFailure>()));
    final text = jsonEncode({
      'format': 'xdownloader.sources',
      'version': 1,
      'sources': [
        {
          'id': 'one',
          'name': 'One',
          'endpoint': 'https://one.test/?url={urlenc}',
          'kind': 'scrape',
          'method': 'GET',
          'body': '',
          'builtin': false,
        },
        {
          'id': 'two',
          'name': 'Two',
          'endpoint': 'https://two.test/?url={urlenc}',
          'kind': 'scrape',
          'method': 'GET',
          'body': '',
          'builtin': false,
        },
      ],
    });
    await expectLater(
      repo.importSources(text, selectedIndices: {9}),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.list.where((s) => !s.builtin), isEmpty);
    expect(await repo.importSources(text, selectedIndices: {1}), 1);
    expect(repo.list.last.name, 'Two');
    repo.dispose();
  });
  const custom = ParseSource(
    'custom',
    'Example',
    'https://example.test/?url={urlenc}',
    SourceKind.scrape,
    'GET',
    '',
    false,
  );
  String packet(List<Map<String, Object?>> sources) => jsonEncode({
    'format': 'xdownloader.sources',
    'version': 1,
    'sources': sources,
  });
  test(
    'source export round trip merges once and preserves selection and fallback',
    () async {
      final source = SourceRepository(MemorySnapshotStore());
      await source.initialize();
      await source.addCustom(custom);
      final destination = SourceRepository(MemorySnapshotStore());
      await destination.initialize();
      await destination.select('fx');
      await destination.setFallback(false);
      expect(await destination.importSources(source.exportSources()), 1);
      expect(await destination.importSources(source.exportSources()), 0);
      expect(destination.list.where((s) => !s.builtin), hasLength(1));
      expect(destination.currentId, 'fx');
      expect(destination.autoFallback, isFalse);
      source.dispose();
      destination.dispose();
    },
  );
  test('invalid later row and failed storage never partially import', () async {
    final store = FailingSourceStore();
    final source = SourceRepository(store);
    await source.initialize();
    final before = source.exportSources();
    await expectLater(
      source.importSources(
        packet([
          custom.toJson(),
          {...custom.toJson(), 'kind': 'script'},
        ]),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(source.exportSources(), before);
    store.fail = true;
    await expectLater(
      source.importSources(packet([custom.toJson()])),
      throwsA(isA<AppFailure>()),
    );
    expect(source.exportSources(), before);
    source.dispose();
  });
  test(
    'imported ids cannot overwrite builtins and content is bounded',
    () async {
      final source = SourceRepository(MemorySnapshotStore());
      await source.initialize();
      final original = source.list.firstWhere((s) => s.id == 'fx');
      expect(
        await source.importSources(
          packet([
            {...custom.toJson(), 'id': 'fx', 'builtin': true},
          ]),
        ),
        1,
      );
      expect(
        source.list.firstWhere((s) => s.id == 'fx').endpoint,
        original.endpoint,
      );
      expect(source.list.last.id, isNot('fx'));
      for (final text in [
        'not-json',
        packet([
          {...custom.toJson(), 'endpoint': 'file:///bad'},
        ]),
        ' ' * (512 * 1024 + 1),
        packet(
          List.generate(
            51,
            (i) => {...custom.toJson(), 'endpoint': 'https://example.test/$i'},
          ),
        ),
      ]) {
        await expectLater(
          source.importSources(text),
          throwsA(isA<AppFailure>()),
        );
      }
      expect(source.list.where((s) => !s.builtin), hasLength(1));
      source.dispose();
    },
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xdownloader/data/repositories/cover_cache_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';

import '../support/app_fixture.dart';

void main() {
  late Directory root;
  late SettingsRepository settings;
  late CoverCacheRepository cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('xdl-covers-');
    settings = SettingsRepository(MemorySnapshotStore());
    await settings.initialize();
    cache = CoverCacheRepository(root: root, settings: settings);
    await cache.initialize();
  });
  tearDown(() async {
    cache.dispose();
    settings.dispose();
    await root.delete(recursive: true);
  });
  test('same-key loads coalesce and cached covers survive restart', () async {
    var calls = 0;
    final gate = Completer<Uint8List?>();
    final one = cache.get('video:a', () {
      calls++;
      return gate.future;
    });
    final two = cache.get('video:a', () async {
      calls++;
      return Uint8List(4);
    });
    gate.complete(Uint8List.fromList([1, 2, 3]));
    expect(await one, [1, 2, 3]);
    expect(await two, [1, 2, 3]);
    expect(calls, 1);
    expect(cache.usedBytes, 3);
    cache.dispose();
    cache = CoverCacheRepository(root: root, settings: settings);
    await cache.initialize();
    expect(
      await cache.get('video:a', () async => throw StateError('must use disk')),
      [1, 2, 3],
    );
    expect(cache.entries, hasLength(1));
  });
  test('LRU evicts the oldest cover and shrinking the persisted limit trims immediately', () async {
    await cache.setLimitMb(1);
    for (final key in ['a', 'b']) {
      await cache.get(key, () async => Uint8List(400000));
    }
    await cache.get('a', () async => null);
    await cache.get('c', () async => Uint8List(400000));
    expect(cache.usedBytes, 800000);
    var reloads = 0;
    await cache.get('a', () async {
      reloads++;
      return null;
    });
    await cache.get('b', () async {
      reloads++;
      return null;
    });
    expect(reloads, 1);
    await cache.setLimitMb(0);
    expect(settings.value.coverCacheLimitMb, 0);
    expect(cache.entries, isEmpty);
    expect(await cache.get('a', () async => Uint8List(5)), hasLength(5));
    expect(cache.usedBytes, 0);
  });
  test('clear during a pending load does not repopulate cache or delete unrelated files', () async {
    final keep = File('${root.path}/keep.txt');
    await keep.writeAsString('keep');
    final gate = Completer<Uint8List?>();
    final pending = cache.get('a', () => gate.future);
    await Future<void>.delayed(Duration.zero);
    await cache.clear();
    gate.complete(Uint8List(8));
    expect(await pending, isNull);
    expect(cache.usedBytes, 0);
    expect(await keep.readAsString(), 'keep');
    await cache.get('a', () async => Uint8List(9));
    expect(cache.usedBytes, 9);
  });
  test(
    'privacy blocks reads/loaders and invalidates work already underway',
    () async {
      final gate = Completer<Uint8List?>();
      final pending = cache.get('a', () => gate.future);
      await Future<void>.delayed(Duration.zero);
      await settings.edit((s) => s.copyWith(privacyMode: true));
      gate.complete(Uint8List(8));
      expect(await pending, isNull);
      expect(
        await cache.get('b', () async => throw StateError('private')),
        isNull,
      );
      expect(cache.usedBytes, 0);
    },
  );
  test('privacy cancels pending remote fetch before a redirect can leave the device', () async {
    cache.dispose();
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    var requests = 0;
    cache = CoverCacheRepository(
      root: root,
      settings: settings,
      client: MockClient((_) async {
        requests++;
        if (!started.isCompleted) started.complete();
        return gate.future;
      }),
    );
    await cache.initialize();
    final pending = cache.remote(
      'post:a',
      Uri.parse('https://images.example/a.jpg'),
    );
    await started.future;
    await settings.edit((s) => s.copyWith(privacyMode: true));
    gate.complete(
      http.Response(
        '',
        302,
        headers: {'location': 'https://other.example/b.jpg'},
      ),
    );
    expect(await pending, isNull);
    expect(requests, 1);
    expect(cache.usedBytes, 0);
  });
  test('disk write failure still returns the loaded cover', () async {
    // A file occupies the directory path; no permission-dependent platform trick.
    await root.delete();
    await File(root.path).writeAsString('blocked');
    try {
      expect(await cache.get('a', () async => Uint8List(4)), hasLength(4));
      expect(cache.entries, isEmpty);
    } finally {
      await File(root.path).delete();
      await root.create();
    }
  });
  test(
    'oversized covers are not cached and limits persist across settings reload',
    () async {
      expect(
        await cache.get(
          'big',
          () async => Uint8List(CoverCacheRepository.maxImageBytes + 1),
        ),
        isNull,
      );
      expect(cache.usedBytes, 0);
      await cache.setLimitMb(47);
      final restored = SettingsRepository(settings.store);
      await restored.initialize();
      expect(restored.value.coverCacheLimitMb, 47);
      restored.dispose();
      await expectLater(cache.setLimitMb(-1), throwsArgumentError);
    },
  );
  test('remote image bytes are cached once, while non-image and oversized responses are ignored', () async {
    cache.dispose();
    var calls = 0;
    cache = CoverCacheRepository(
      root: root,
      settings: settings,
      client: MockClient((request) async {
        calls++;
        if (request.url.path == '/html') {
          return http.Response(
            '<html/>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response.bytes(
          request.url.path == '/big'
              ? Uint8List(CoverCacheRepository.maxImageBytes + 1)
              : [1, 2, 3],
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      }),
    );
    await cache.initialize();
    final good = Uri.parse('https://images.example/a.jpg');
    expect(await cache.remote('good', good), [1, 2, 3]);
    expect(await cache.remote('good', good), [1, 2, 3]);
    expect(calls, 1);
    expect(
      await cache.remote('bad', Uri.parse('https://images.example/html')),
      isNull,
    );
    expect(
      await cache.remote('big', Uri.parse('https://images.example/big')),
      isNull,
    );
    expect(cache.usedBytes, 3);
  });
}

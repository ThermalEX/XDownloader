import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/repositories/cover_cache_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';

import '../support/app_fixture.dart';

void main() {
  late Directory root;
  late SettingsRepository settings;
  late CoverCacheRepository cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('xdl-cover-memory-');
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

  Future<Uint8List?> missing() async => null;

  test(
    'hot hits reuse bytes without reading or touching the disk file',
    () async {
      final original = await cache.get(
        'a',
        () async => Uint8List.fromList([1, 2]),
      );
      final file = cache.entries.single.file;
      final marker = DateTime(2001);
      await file.setLastModified(marker);
      expect(identical(await cache.get('a', missing), original), isTrue);
      expect(await file.lastModified(), marker);
      // A hot image may remain usable until explicit cache invalidation.
      await file.delete();
      expect(await cache.get('a', missing), [1, 2]);
    },
  );

  test('a restored disk cover becomes a reusable warm hit', () async {
    await cache.get('a', () async => Uint8List.fromList([3, 4]));
    cache.dispose();
    cache = CoverCacheRepository(root: root, settings: settings);
    await cache.initialize();
    final first = await cache.get('a', missing);
    await cache.entries.single.file.delete();
    expect(identical(await cache.get('a', missing), first), isTrue);
    expect(first, [3, 4]);
  });

  test('hot access timestamps coalesce into one deferred disk batch', () async {
    final timers = <_AccessTimer>[];
    await runZoned(
      () async {
        await cache.get('a', () async => Uint8List(8));
        final file = cache.entries.single.file;
        final marker = DateTime(2001);
        await file.setLastModified(marker);
        for (var index = 0; index < 4; index++) {
          await cache.get('a', missing);
        }
        expect(timers, hasLength(1));
        expect(await file.lastModified(), marker);
        timers.single.fire();
        // A following queued lookup waits for the deferred metadata batch.
        await cache.get('barrier', missing);
        expect((await file.lastModified()).isAfter(marker), isTrue);
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration != const Duration(seconds: 30)) {
            return parent.createTimer(zone, duration, callback);
          }
          final timer = _AccessTimer(callback);
          timers.add(timer);
          return timer;
        },
      ),
    );
  });

  test(
    'memory LRU bounds entry count and promotes the most recent hit',
    () async {
      for (var index = 0; index < 32; index++) {
        await cache.get(
          'cover:$index',
          () async => Uint8List.fromList([index]),
        );
      }
      await cache.get('cover:0', missing);
      await cache.get('cover:32', () async => Uint8List.fromList([32]));
      for (final entry in cache.entries) {
        await entry.file.delete();
      }
      expect(await cache.get('cover:0', missing), [0]);
      expect(await cache.get('cover:1', missing), isNull);
      expect(await cache.get('cover:32', missing), [32]);
    },
  );

  test('memory LRU retains at most eight MiB of cover bytes', () async {
    const size = 3 * 1024 * 1024;
    for (final key in ['a', 'b', 'c']) {
      await cache.get(key, () async => Uint8List(size));
    }
    for (final entry in cache.entries) {
      await entry.file.delete();
    }
    expect(await cache.get('a', missing), isNull);
    expect(await cache.get('b', missing), hasLength(size));
    expect(await cache.get('c', missing), hasLength(size));
  });

  test('memory access order still governs disk LRU eviction', () async {
    await cache.setLimitMb(1);
    await cache.get('a', () async => Uint8List(400000));
    await cache.get('b', () async => Uint8List(400000));
    await cache.get('a', missing);
    await cache.get('c', () async => Uint8List(400000));
    expect(cache.usedBytes, 800000);
    expect(await cache.get('a', missing), hasLength(400000));
    expect(await cache.get('b', missing), isNull);
  });

  test('privacy purges warm bytes before unlocking again', () async {
    await cache.get('a', () async => Uint8List(8));
    final pending = cache.get('a', missing);
    await settings.edit((s) => s.copyWith(privacyMode: true));
    // The settings write may complete after a synchronous hot hit. Privacy must
    // block subsequent hits and the in-memory bytes must be gone on unlock.
    await pending;
    expect(await cache.get('a', missing), isNull);
    await cache.entries.single.file.delete();
    await settings.setPrivacyMode(false);
    expect(await cache.get('a', missing), isNull);
  });

  test('direct settings shrink also invalidates warm entries', () async {
    await cache.get('a', () async => Uint8List(8));
    await cache.entries.single.file.delete();
    await settings.edit((s) => s.copyWith(coverCacheLimitMb: 1));
    expect(await cache.get('a', missing), isNull);
  });

  test(
    'clear invalidates an already queued warm hit and allows a new load',
    () async {
      await cache.get('a', () async => Uint8List(8));
      final pending = cache.get('a', missing);
      final clearing = cache.clear();
      expect(await pending, isNull);
      await clearing;
      expect(await cache.get('a', missing), isNull);
      expect(await cache.get('a', () async => Uint8List(9)), hasLength(9));
    },
  );

  test(
    'shrinking clears memory and invalidates a loader already in flight',
    () async {
      await cache.get('warm', () async => Uint8List(8));
      final warmFile = cache.entries.single.file;
      final gate = Completer<Uint8List?>();
      final started = Completer<void>();
      final pending = cache.get('pending', () {
        started.complete();
        return gate.future;
      });
      await started.future;
      await cache.setLimitMb(1);
      gate.complete(Uint8List(9));
      expect(await pending, isNull);
      await warmFile.delete();
      expect(await cache.get('warm', missing), isNull);
      expect(cache.entries.any((entry) => entry.bytes == 9), isFalse);
    },
  );

  test('a zero limit does not retain bytes in memory or on disk', () async {
    await cache.setLimitMb(0);
    var calls = 0;
    Future<Uint8List?> load() async {
      calls++;
      return Uint8List(5);
    }

    expect(await cache.get('a', load), hasLength(5));
    expect(await cache.get('a', load), hasLength(5));
    expect(calls, 2);
    expect(cache.entries, isEmpty);
  });

  test('dispose invalidates a queued warm hit and all future reads', () async {
    await cache.get('a', () async => Uint8List(8));
    final pending = cache.get('a', missing);
    cache.dispose();
    expect(await pending, isNull);
    expect(await cache.get('a', missing), isNull);
    // Keep teardown ownership simple without double-disposing a notifier.
    cache = CoverCacheRepository(root: root, settings: settings);
    await cache.initialize();
  });
}

class _AccessTimer implements Timer {
  _AccessTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/data/repositories/update_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';

import '../support/fake_update_backend.dart';
import '../support/update_fixture.dart';

class UpdateTestStore extends SnapshotStore {
  UpdateTestStore(super.directory);
  bool fail = false;
  @override
  Future<void> write(String key, Map<String, Object?> value) async {
    if (fail) throw const AppFailure(FailureKind.storage, 'write failed');
    return super.write(key, value);
  }
}

ReleaseCheck result(UpdateChannel channel) => ReleaseCheck(
  candidate: fixtureUpdate(channel: channel),
  scopeComplete: true,
  skippedReleases: 0,
  validReleases: 1,
);
void main() {
  late Directory temp;
  late UpdateTestStore store;
  late FakeUpdateBackend backend;
  late FixtureReleaseClient client;
  late UpdateRepository repo;
  var now = DateTime.utc(2026, 10, 21, 2);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-updates-');
    store = UpdateTestStore(temp);
    backend = FakeUpdateBackend();
    client = FixtureReleaseClient();
    now = DateTime.utc(2026, 10, 21, 2);
    repo = UpdateRepository(
      store: store,
      releases: client,
      backend: backend,
      now: () => now,
    );
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await temp.delete(recursive: true);
  });
  test('stable default and exactly daily automatic checks preserve unrelated settings', () async {
    await store.write('settings', {'privacyMode': true});
    expect(repo.preferences.channel, UpdateChannel.stable);
    expect(repo.preferences.autoCheck, true);
    await Future.wait([
      repo.check(automatic: true),
      repo.check(automatic: true),
    ]);
    expect(client.checks, 1);
    now = now.add(const Duration(hours: 23));
    await repo.check(automatic: true);
    expect(client.checks, 1);
    now = now.add(const Duration(hours: 1));
    await repo.check(automatic: true);
    expect(client.checks, 2);
    await repo.check();
    expect(client.checks, 3);
    expect((await store.read('settings'))['privacyMode'], true);
  });
  test('failed automatic attempt is throttled and clock rollback permits one new attempt', () async {
    client.respond = (_) =>
        Future.error(const AppFailure(FailureKind.network, 'offline'));
    await repo.check(automatic: true);
    expect(repo.error, isNotNull);
    await repo.check(automatic: true);
    expect(client.checks, 1);
    now = now.subtract(const Duration(days: 1));
    await repo.check(automatic: true);
    expect(client.checks, 2);
    await repo.check(automatic: true);
    expect(client.checks, 2);
  });
  test('late stable reply cannot overwrite selected beta channel', () async {
    final stable = Completer<ReleaseCheck>();
    client.respond = (channel) => channel == UpdateChannel.stable
        ? stable.future
        : Future.value(result(channel));
    final first = repo.check();
    await Future<void>.delayed(Duration.zero);
    await repo.setChannel(UpdateChannel.beta);
    stable.complete(result(UpdateChannel.stable));
    await first;
    expect(repo.preferences.channel, UpdateChannel.beta);
    expect(repo.result!.candidate!.channel, UpdateChannel.beta);
  });
  test('preference write failure does not change channel', () async {
    store.fail = true;
    await expectLater(
      repo.setChannel(UpdateChannel.beta),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.preferences.channel, UpdateChannel.stable);
  });
  test(
    'active native update blocks switching until explicitly cancelled',
    () async {
      client.respond = (channel) async => result(channel);
      await repo.check();
      await repo.download();
      await expectLater(
        repo.setChannel(UpdateChannel.beta),
        throwsA(isA<AppFailure>()),
      );
      expect(repo.preferences.channel, UpdateChannel.stable);
      await repo.cancelDownload();
      await repo.setChannel(UpdateChannel.beta);
      expect(repo.preferences.channel, UpdateChannel.beta);
      expect(backend.calls, ['enqueue', 'cancel']);
    },
  );
  test('restored ready state installs by persisted native identity without release fetch', () async {
    backend.transfer = const UpdateTransfer(
      candidateId: 'saved',
      phase: UpdatePhase.permissionRequired,
    );
    await repo.refreshTransfer();
    await repo.install();
    expect(backend.calls, ['install:saved']);
    expect(client.checks, 0);
  });
  test(
    'dispose invalidates async results without cancelling a native download',
    () async {
      final pending = Completer<ReleaseCheck>();
      client.respond = (_) => pending.future;
      final future = repo.check();
      await Future<void>.delayed(Duration.zero);
      repo.dispose();
      pending.complete(result(UpdateChannel.stable));
      await future;
      expect(backend.calls, isEmpty);
      // tearDown disposes a fresh instance, not the already-disposed notifier.
      repo = UpdateRepository(
        store: store,
        releases: FixtureReleaseClient(),
        backend: backend,
      );
    },
  );
  test(
    'corrupt update preferences do not block app or overwrite original file',
    () async {
      await File('${temp.path}/updates.json').writeAsString('damaged');
      repo.dispose();
      client = FixtureReleaseClient();
      repo = UpdateRepository(store: store, releases: client, backend: backend);
      await repo.initialize();
      expect(repo.error, isNotNull);
      expect(repo.preferences.autoCheck, false);
      expect(await File('${temp.path}/updates.json').readAsString(), 'damaged');
    },
  );
  test(
    'platform failure remains local to updates and manual check can retry',
    () async {
      backend.readError = const AppFailure(FailureKind.storage, 'read failed');
      await repo.initialize();
      expect(repo.error, isNotNull);
      backend.readError = null;
      await repo.check();
      expect(repo.installed, isNotNull);
    },
  );
  test(
    'valid backup restores channel after current preferences are damaged',
    () async {
      await repo.setChannel(UpdateChannel.beta);
      await repo.setAutoCheck(false);
      await repo.setAutoCheck(false);
      await File('${temp.path}/updates.json').writeAsString('damaged');
      repo.dispose();
      client = FixtureReleaseClient();
      repo = UpdateRepository(store: store, releases: client, backend: backend);
      await repo.initialize();
      expect(repo.preferences.channel, UpdateChannel.beta);
      expect(repo.preferences.autoCheck, false);
      expect(repo.error, isNull);
    },
  );
}

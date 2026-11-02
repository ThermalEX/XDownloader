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
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-updates-');
    store = UpdateTestStore(temp);
    backend = FakeUpdateBackend();
    client = FixtureReleaseClient();
    repo = UpdateRepository(store: store, releases: client, backend: backend);
    await repo.initialize();
  });
  tearDown(() async {
    repo.dispose();
    await temp.delete(recursive: true);
  });

  const ready = UpdateTransfer(candidateId: 'saved', phase: UpdatePhase.ready);
  Future<void> settleAutoInstall() => Future<void>.delayed(Duration.zero);

  test('explicit installer outcome consumes a manual attempt after granting permission', () async {
    backend.transfer = const UpdateTransfer(
      candidateId: 'saved',
      phase: UpdatePhase.permissionRequired,
    );
    await repo.refreshTransfer();
    backend.transfer = ready;
    backend.installResponse = (_) async => const UpdateTransfer(
      candidateId: 'saved',
      phase: UpdatePhase.ready,
      installOutcome: UpdateInstallOutcome.installer,
    );
    await repo.install();
    repo.setForegroundVisible(true);
    await settleAutoInstall();
    expect(backend.calls, ['install:saved']);
  });

  test('a fresh resumed signal retries native deferral even when a visibility owner already exists', () async {
    backend.transfer = ready;
    backend.installResponse = (_) async => backend.calls.length == 1
        ? const UpdateTransfer(
            candidateId: 'saved',
            phase: UpdatePhase.ready,
            installOutcome: UpdateInstallOutcome.deferred,
          )
        : const UpdateTransfer(
            candidateId: 'saved',
            phase: UpdatePhase.ready,
            installOutcome: UpdateInstallOutcome.installer,
          );
    repo.setForegroundVisible(true);
    await settleAutoInstall();
    expect(backend.calls, ['install:saved']);
    repo.setForegroundVisible(true);
    await settleAutoInstall();
    expect(backend.calls, ['install:saved', 'install:saved']);
  });

  test(
    'only a verified ready transfer opens the installer automatically once',
    () async {
      repo.setForegroundVisible(true);
      for (final phase in [
        UpdatePhase.queued,
        UpdatePhase.running,
        UpdatePhase.verifying,
      ]) {
        backend.transfer = UpdateTransfer(candidateId: 'saved', phase: phase);
        await repo.refreshTransfer();
        await settleAutoInstall();
        expect(backend.calls, isEmpty);
      }
      backend.transfer = ready;
      await repo.refreshTransfer();
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
      await repo.refreshTransfer();
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
    },
  );

  test('background completion waits for foreground, returning from installer does not reopen it', () async {
    backend.transfer = ready;
    await repo.refreshTransfer();
    await settleAutoInstall();
    expect(backend.calls, isEmpty);
    final shell = Object(), dialog = Object();
    repo.setForegroundVisible(true, owner: shell);
    repo.setForegroundVisible(true, owner: dialog);
    await settleAutoInstall();
    expect(backend.calls, ['install:saved']);
    repo.setForegroundVisible(false, owner: shell);
    repo.setForegroundVisible(false, owner: dialog);
    repo.setForegroundVisible(true, owner: shell);
    await settleAutoInstall();
    expect(backend.calls, ['install:saved']);
  });

  test(
    'recovered ready package opens installer without fetching releases',
    () async {
      backend.transfer = ready;
      await repo.initialize();
      repo.setForegroundVisible(true);
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
      expect(client.checks, 0);
    },
  );

  for (final grant in [true, false]) {
    test(
      'permission settings return resumes installation only when granted=$grant',
      () async {
        backend.transfer = ready;
        backend.installResponse = (_) async {
          if (backend.calls.length == 1) {
            backend.transfer = const UpdateTransfer(
              candidateId: 'saved',
              phase: UpdatePhase.permissionRequired,
            );
          }
          return backend.transfer;
        };
        repo.setForegroundVisible(true);
        await settleAutoInstall();
        expect(backend.calls, ['install:saved']);
        expect(repo.transfer.phase, UpdatePhase.permissionRequired);
        repo.setForegroundVisible(false);
        if (grant) backend.transfer = ready;
        repo.setForegroundVisible(true);
        await settleAutoInstall();
        expect(
          backend.calls,
          grant ? ['install:saved', 'install:saved'] : ['install:saved'],
        );
        repo.setForegroundVisible(false);
        repo.setForegroundVisible(true);
        await settleAutoInstall();
        expect(backend.calls.length, grant ? 2 : 1);
      },
    );
  }

  test(
    'automatic install errors do not loop and remain manually retryable',
    () async {
      backend.transfer = ready;
      backend.installResponse = (_) async =>
          throw const AppFailure(FailureKind.storage, '安装器不可用');
      repo.setForegroundVisible(true);
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
      expect(repo.error?.message, '安装器不可用');
      await repo.refreshTransfer();
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
      backend.installResponse = null;
      await repo.install();
      expect(backend.calls, ['install:saved', 'install:saved']);
      expect(repo.error, isNull);
    },
  );

  test(
    'manual retry during automatic launch shares the in-flight installation',
    () async {
      final pending = Completer<UpdateTransfer>();
      backend.transfer = ready;
      backend.installResponse = (_) => pending.future;
      repo.setForegroundVisible(true);
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
      final manual = repo.install();
      pending.complete(ready);
      await manual;
      await settleAutoInstall();
      expect(backend.calls, ['install:saved']);
    },
  );

  for (final phase in [UpdatePhase.failed, UpdatePhase.cancelled]) {
    test('$phase never opens the installer', () async {
      backend.transfer = UpdateTransfer(candidateId: 'saved', phase: phase);
      repo.setForegroundVisible(true);
      await settleAutoInstall();
      expect(backend.calls, isEmpty);
    });
  }

  test('queued automatic launch rechecks visibility before invoking native install', () async {
    backend.transfer = ready;
    repo.setForegroundVisible(true);
    await repo.refreshTransfer();
    repo.setForegroundVisible(false);
    await settleAutoInstall();
    expect(backend.calls, isEmpty);
  });

  test(
    'redownloading the same release gets a fresh automatic installer attempt',
    () async {
      client.respond = (channel) async => result(channel);
      await repo.check();
      repo.setForegroundVisible(true);
      final id = fixtureUpdate().candidateId;
      for (var download = 0; download < 2; download++) {
        await repo.download();
        backend.transfer = UpdateTransfer(
          candidateId: id,
          phase: UpdatePhase.ready,
        );
        await repo.refreshTransfer();
        await settleAutoInstall();
        if (download == 0) await repo.cancelDownload();
      }
      expect(backend.calls, [
        'enqueue',
        'install:$id',
        'cancel',
        'enqueue',
        'install:$id',
      ]);
    },
  );

  for (final returnedPhase in [
    UpdatePhase.ready,
    UpdatePhase.permissionRequired,
  ]) {
    test(
      'fast permission return reconciles even while native result is still pending: $returnedPhase',
      () async {
        final pending = Completer<UpdateTransfer>();
        backend.transfer = ready;
        backend.installResponse = (_) =>
            backend.calls.length == 1 ? pending.future : Future.value(ready);
        repo.setForegroundVisible(true);
        await settleAutoInstall();
        expect(backend.calls, ['install:saved']);
        repo.setForegroundVisible(false);
        repo.setForegroundVisible(true);
        pending.complete(
          UpdateTransfer(
            candidateId: 'saved',
            phase: returnedPhase,
            installOutcome: UpdateInstallOutcome.permissionRequired,
          ),
        );
        await settleAutoInstall();
        expect(backend.calls, ['install:saved', 'install:saved']);
        await repo.refreshTransfer();
        await settleAutoInstall();
        expect(backend.calls.length, 2);
      },
    );
  }

  for (final resumeBeforeReply in [true, false]) {
    test(
      'native foreground deferral retries only after resume, early resume=$resumeBeforeReply',
      () async {
        final pending = Completer<UpdateTransfer>();
        backend.transfer = ready;
        backend.installResponse = (_) =>
            backend.calls.length == 1 ? pending.future : Future.value(ready);
        repo.setForegroundVisible(true);
        await settleAutoInstall();
        repo.setForegroundVisible(false);
        if (resumeBeforeReply) repo.setForegroundVisible(true);
        pending.complete(
          const UpdateTransfer(
            candidateId: 'saved',
            phase: UpdatePhase.ready,
            installOutcome: UpdateInstallOutcome.deferred,
          ),
        );
        await settleAutoInstall();
        if (!resumeBeforeReply) {
          expect(backend.calls, ['install:saved']);
          repo.setForegroundVisible(true);
          await settleAutoInstall();
        }
        expect(backend.calls, ['install:saved', 'install:saved']);
        await repo.refreshTransfer();
        await settleAutoInstall();
        expect(backend.calls.length, 2);
      },
    );
  }
  for (final autoCheck in [true, false]) {
    test(
      'transient platform failure preserves startup preferences $autoCheck',
      () async {
        await repo.setChannel(UpdateChannel.beta);
        await repo.setShowUpdatePrompt(false);
        await repo.setAutoCheck(autoCheck);
        final before = await store.read('updates');
        final checks = client.checks;
        backend.readError = const AppFailure(FailureKind.storage, '暂时不可用');
        await repo.initialize();
        expect(repo.preferences.autoCheck, autoCheck);
        expect(repo.preferences.channel, UpdateChannel.beta);
        expect(repo.preferences.showUpdatePrompt, false);
        expect(repo.error, isNotNull);
        backend.readError = null;
        client.respond = (channel) async => result(channel);
        await repo.check(automatic: true);
        expect(client.checks, checks + (autoCheck ? 1 : 0));
        expect(await store.read('updates'), before);
      },
    );
  }
  test(
    'automatic checks coalesce in flight but run again at the next startup',
    () async {
      await store.write('settings', {'privacyMode': true});
      expect(repo.preferences.channel, UpdateChannel.stable);
      expect(repo.preferences.autoCheck, true);
      await Future.wait([
        repo.check(automatic: true),
        repo.check(automatic: true),
      ]);
      expect(client.checks, 1);
      await repo.check(automatic: true);
      expect(client.checks, 2);
      await repo.check(automatic: true);
      expect(client.checks, 3);
      await repo.check();
      expect(client.checks, 4);
      expect((await store.read('settings'))['privacyMode'], true);
    },
  );
  test('failed automatic checks can retry on the next startup without a daily limit', () async {
    client.respond = (_) =>
        Future.error(const AppFailure(FailureKind.network, 'offline'));
    await repo.check(automatic: true);
    expect(repo.error, isNotNull);
    await repo.check(automatic: true);
    expect(client.checks, 2);
    await repo.check(automatic: true);
    expect(client.checks, 3);
    await repo.check(automatic: true);
    expect(client.checks, 4);
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
  test('reminder preference persists independently and failed writes keep the old value', () async {
    await repo.setShowUpdatePrompt(false);
    await repo.setChannel(UpdateChannel.beta);
    await repo.initialize();
    expect(repo.preferences.showUpdatePrompt, false);
    expect(repo.preferences.autoCheck, true);
    expect(repo.preferences.channel, UpdateChannel.beta);
    store.fail = true;
    await expectLater(
      repo.setShowUpdatePrompt(true),
      throwsA(isA<AppFailure>()),
    );
    expect(repo.preferences.showUpdatePrompt, false);
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
      await repo.setShowUpdatePrompt(false);
      await repo.setAutoCheck(false);
      await repo.setAutoCheck(false);
      await File('${temp.path}/updates.json').writeAsString('damaged');
      repo.dispose();
      client = FixtureReleaseClient();
      repo = UpdateRepository(store: store, releases: client, backend: backend);
      await repo.initialize();
      expect(repo.preferences.channel, UpdateChannel.beta);
      expect(repo.preferences.autoCheck, false);
      expect(repo.preferences.showUpdatePrompt, false);
      expect(repo.error, isNull);
    },
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xdownloader/data/backup/backup_archive.dart';
import 'package:xdownloader/data/backup/webdav_client.dart';
import 'package:xdownloader/data/repositories/backup_repository.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/data/repositories/update_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/platform/backup_platform.dart';

import '../support/fake_update_backend.dart';

void main() {
  late Directory dir;
  late SnapshotStore store;
  late SettingsRepository settings;
  late FavoriteRepository favorites;
  late SourceRepository sources;
  late UpdateRepository updates;
  late BackupRepository backups;
  late Future<http.Response> Function(http.Request) respond;
  final passwords = <String, String>{};
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('xdl-backup-repo-');
    store = SnapshotStore(dir);
    settings = SettingsRepository(store);
    favorites = FavoriteRepository(store);
    sources = SourceRepository(store);
    updates = UpdateRepository(
      store: store,
      releases: FixtureReleaseClient(),
      backend: FakeUpdateBackend(),
    );
    await settings.initialize();
    await favorites.initialize();
    await sources.initialize();
    await updates.initialize();
    passwords.clear();
    respond = (_) async => http.Response('offline', 503);
    backups = BackupRepository(
      store: store,
      settings: settings,
      favorites: favorites,
      sources: sources,
      updates: updates,
      platform: BackupPlatform(
        call: (method, args) async {
          final key = args['key'] as String? ?? 'default';
          if (method == 'backupReadPassword') return passwords[key] ?? '';
          if (method == 'backupWritePassword') {
            passwords[key] = args['password'] as String;
          }
          return null;
        },
      ),
      clientFactory: (config, password, cancelled) => WebDavClient(
        config: config,
        password: password,
        isCancelled: cancelled,
        client: MockClient((r) => respond(r)),
      ),
    );
    await backups.initialize();
  });
  tearDown(() async {
    backups.dispose();
    updates.dispose();
    settings.dispose();
    favorites.dispose();
    sources.dispose();
    await dir.delete(recursive: true);
  });
  test(
    'multiple local timestamps persist without changing live favorites',
    () async {
      await favorites.add(
        'https://x.com/sample/status/1234567890',
        title: 'first',
      );
      final first = await backups.create(location: BackupLocation.local);
      await favorites.add(
        'https://x.com/sample/status/4567890123',
        title: 'second',
      );
      final second = await backups.create(location: BackupLocation.local);
      expect(first.id, isNot(second.id));
      expect(backups.localArchives.length, 2);
      expect(favorites.items.length, 2);
      expect(first.data['settings']!.containsKey('privacyPasswordHash'), false);
      expect(first.data['favorites']!['items'], hasLength(1));
    },
  );
  test('restore rejects stale preview and preserves latest edit', () async {
    final archive = await backups.create(location: BackupLocation.local);
    final preview = await backups.preview(archive, replace: true);
    await favorites.add('https://x.com/sample/status/1234567890', title: 'new');
    await expectLater(backups.restore(preview), throwsA(isA<Exception>()));
    expect(favorites.items.single.title, 'new');
  });
  test(
    'replace creates safety archive and queued edit sees restored state',
    () async {
      await favorites.add(
        'https://x.com/sample/status/1234567890',
        title: 'saved',
      );
      final archive = await backups.create(location: BackupLocation.local);
      await favorites.remove('1234567890');
      final preview = await backups.preview(archive, replace: true);
      await backups.restore(preview);
      expect(favorites.items.single.title, 'saved');
      expect(backups.localArchives.length, 2);
      final reopened = FavoriteRepository(SnapshotStore(dir));
      await reopened.initialize();
      expect(reopened.items.single.title, 'saved');
      reopened.dispose();
    },
  );
  test(
    'cloud failure retains local backup and reports partial success',
    () async {
      await backups.configure(
        config: WebDavConfig(
          endpoint: Uri.parse('https://dav.test/dav/'),
          username: 'a',
        ),
        password: 'secret',
        deviceName: 'test',
        autoCheck: true,
      );
      await expectLater(
        backups.create(location: BackupLocation.both),
        throwsA(isA<Exception>()),
      );
      expect(backups.localArchives, hasLength(1));
      expect(backups.status, contains('本地已保存'));
      expect(passwords.values, contains('secret'));
      expect(
        await File('${dir.path}/sync.json').readAsString(),
        isNot(contains('secret')),
      );
    },
  );
  test('privacy blocks existing archives actions and pending privacy intent cancels', () async {
    final archive = await backups.create(location: BackupLocation.local);
    final hold = Completer<void>();
    final gate = store.mutations.run(() => hold.future);
    final enabling = settings.setPrivacyMode(true);
    expect(backups.isPrivate, true);
    expect(backups.localArchives, isEmpty);
    await expectLater(
      backups.create(location: BackupLocation.local),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      backups.preview(archive, replace: false),
      throwsA(isA<Exception>()),
    );
    await expectLater(backups.refreshRemote(), throwsA(isA<Exception>()));
    hold.complete();
    await gate;
    await enabling;
    expect(backups.pendingCloudCount, 0);
  });
  test('blank secret retains same account password without copying it to a different account', () async {
    final config = WebDavConfig(
      endpoint: Uri.parse('https://dav.test/dav/'),
      username: 'a',
    );
    await backups.configure(
      config: config,
      password: 'original',
      deviceName: 'phone',
      autoCheck: true,
    );
    await backups.configure(
      config: config,
      password: '',
      deviceName: 'renamed',
      autoCheck: true,
    );
    var key = (await store.read('sync'))['credentialKey'] as String;
    expect(passwords[key], 'original');
    await backups.configure(
      config: WebDavConfig(endpoint: config.endpoint, username: 'different'),
      password: '',
      deviceName: 'phone',
      autoCheck: true,
    );
    key = (await store.read('sync'))['credentialKey'] as String;
    expect(passwords[key], '');
  });
  test('older selected cloud snapshot downloads without restoring current data', () async {
    BackupArchive remote(String id, int month) => BackupArchive.create(
      id: id,
      createdAt: DateTime.utc(2026, month),
      deviceId: 'other',
      deviceName: 'other phone',
      appVersion: 'test',
      data: {
        'favorites': {'items': [], 'categories': []},
      },
    );
    final old = remote('old', 1), recent = remote('recent', 2);
    final gets = <String>[];
    respond = (request) async {
      if (request.method == 'PROPFIND') {
        return http.Response(
          '''<d:multistatus xmlns:d="DAV:">${[old, recent].map((a) => '<d:response><d:href>/dav/XDownloader/${a.fileName}</d:href><d:propstat><d:prop><d:getetag>"${a.id}"</d:getetag><d:getlastmodified>${HttpDate.format(a.createdAt)}</d:getlastmodified></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>').join()}</d:multistatus>''',
          207,
        );
      }
      gets.add(request.url.path);
      return http.Response.bytes(old.encode(), 200);
    };
    await backups.configure(
      config: WebDavConfig(
        endpoint: Uri.parse('https://dav.test/dav/'),
        username: 'user',
      ),
      password: 'p',
      deviceName: 'phone',
      autoCheck: true,
    );
    await favorites.add(
      'https://x.com/sample/status/1234567890',
      title: 'local',
    );
    await backups.checkAtStartup();
    expect(backups.remoteEntries, hasLength(2));
    expect(backups.pendingCloudCount, 2);
    final chosen = backups.remoteEntries.singleWhere(
      (e) => e.name == old.fileName,
    );
    final downloaded = await backups.download(chosen);
    expect(downloaded.id, 'old');
    expect(gets, [chosen.uri.path]);
    expect(favorites.items.single.title, 'local');
    expect(backups.pendingCloudCount, 2, reason: 'download is not restore');
    await backups.restore(await backups.preview(downloaded, replace: true));
    expect(favorites.items, isEmpty);
    expect(backups.pendingCloudCount, 1);
  });
  test(
    'privacy during stalled cloud read cancels without a local archive',
    () async {
      final pending = Completer<http.Response>(), started = Completer<void>();
      respond = (_) {
        started.complete();
        return pending.future;
      };
      await backups.configure(
        config: WebDavConfig(
          endpoint: Uri.parse('https://dav.test/dav/'),
          username: 'a',
        ),
        password: 'p',
        deviceName: 'phone',
        autoCheck: true,
      );
      final downloading = backups.download(
        WebDavEntry(
          uri: Uri.parse('https://dav.test/dav/XDownloader/a.zip'),
          name: 'a.zip',
        ),
      );
      final failure = expectLater(downloading, throwsA(isA<Exception>()));
      await started.future;
      await settings.setPrivacyMode(true);
      await failure;
      pending.complete(http.Response(jsonEncode({}), 200));
      expect(backups.localArchives, isEmpty);
      expect(
        await Directory('${dir.path}/backups')
            .list()
            .where((f) => f.path.endsWith('.zip'))
            .length,
        0,
      );
    },
  );
  test(
    'privacy cache clearing cannot allow a durable archive ID collision',
    () async {
      final first = await backups.create(location: BackupLocation.local);
      await backups.configure(
        config: WebDavConfig(
          endpoint: Uri.parse('https://dav.test/dav/'),
          username: 'a',
        ),
        password: 'p',
        deviceName: 'phone',
        autoCheck: false,
      );
      await settings.setPrivacyMode(true);
      await settings.setPrivacyMode(false);
      final conflict = BackupArchive.create(
        id: first.id,
        createdAt: first.createdAt.add(const Duration(seconds: 1)),
        deviceId: first.deviceId,
        deviceName: first.deviceName,
        appVersion: first.appVersion,
        data: {
          'favorites': {
            'items': [],
            'categories': ['different'],
          },
        },
      );
      respond = (_) async => http.Response.bytes(conflict.encode(), 200);
      await expectLater(
        backups.download(
          WebDavEntry(
            uri: Uri.parse('https://dav.test/dav/XDownloader/conflict.zip'),
            name: 'conflict.zip',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        await Directory('${dir.path}/backups')
            .list()
            .where((f) => f.path.endsWith('.zip'))
            .length,
        1,
      );
    },
  );
  test('own verified upload without ETag is not a new foreign cloud archive', () async {
    final archive = await backups.create(location: BackupLocation.local);
    respond = (r) async {
      if (r.method == 'MKCOL' || r.method == 'PUT') {
        return http.Response('', 201);
      }
      if (r.method == 'GET') return http.Response.bytes(archive.encode(), 200);
      return http.Response(
        '<d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/XDownloader/${archive.fileName}</d:href><d:propstat><d:prop><d:getlastmodified>Mon, 02 Nov 2026 00:00:00 GMT</d:getlastmodified><d:getcontentlength>${archive.encode().length}</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>',
        207,
      );
    };
    await backups.configure(
      config: WebDavConfig(
        endpoint: Uri.parse('https://dav.test/dav/'),
        username: 'a',
      ),
      password: 'p',
      deviceName: 'phone',
      autoCheck: true,
    );
    await backups.upload(archive);
    await backups.checkAtStartup();
    expect(backups.pendingCloudCount, 0);
  });
}

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/repositories/download_repository.dart';
import '../data/repositories/download_retry_resolver.dart';
import '../data/repositories/cover_cache_repository.dart';
import '../data/repositories/source_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/favorite_repository.dart';
import '../data/repositories/update_repository.dart';
import '../data/updates/github_release_client.dart';
import '../platform/android_update_backend.dart';
import '../platform/android_privacy_passwords.dart';
import '../data/legacy_migration.dart';
import '../platform/share_gateway.dart';
import '../core/parsing/parse_client.dart';

import 'dart:io';

import '../data/storage/snapshot_store.dart';
import '../platform/android_download_backend.dart';
import '../platform/legacy_data_gateway.dart';
import '../platform/platform_bridge.dart';

class AppDependencies {
  AppDependencies({
    required this.downloads,
    required this.sources,
    required this.settings,
    required this.favorites,
    required this.shares,
    required this.parser,
    required this.updates,
    Future<String?> Function()? readClipboard,
    Future<void> Function()? prepareDownload,
    this.migration,
  }) : readClipboard =
           readClipboard ??
           (() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text),
       prepareDownload = prepareDownload ?? (() async {});
  final DownloadRepository downloads;
  final SourceRepository sources;
  final SettingsRepository settings;
  final FavoriteRepository favorites;
  final ShareGateway shares;
  final ParseClient parser;
  final UpdateRepository updates;
  final Future<String?> Function() readClipboard;
  final Future<void> Function() prepareDownload;
  final MigrationResult? migration;
}

Future<AppDependencies> bootstrap() async {
  final path = await callPlatform('supportDirectory', {}) as String;
  final store = SnapshotStore(Directory('$path/flutter_data'));
  final migration = await LegacyMigration(store, LegacyDataGateway()).run();
  final sources = SourceRepository(store);
  final parser = ParseClient(onAttempt: sources.recordAttempt);
  final retryResolver = DownloadRetryResolver(
    parsePost: (input, cancellation) =>
        sources.runParse(parser, input, cancellation),
  );
  final settings = SettingsRepository(
    store,
    passwords: AndroidPrivacyPasswords(),
  );
  final favorites = FavoriteRepository(store);
  final backend = AndroidDownloadBackend();
  final cachePath = await callPlatform('cacheDirectory', {}) as String;
  final covers = CoverCacheRepository(
    root: Directory('$cachePath/xdl_video_covers'),
    settings: settings,
  );
  final downloads = DownloadRepository(
    store: store,
    backend: backend,
    coverCache: covers,
    refreshRequest: retryResolver.call,
  );
  final updates = UpdateRepository(
    store: store,
    releases: GitHubReleaseClient(client: http.Client()),
    backend: AndroidUpdateBackend(),
  );
  try {
    await sources.initialize();
    await settings.initialize();
    try {
      await covers.initialize();
    } on FileSystemException {
      /* Disposable cache is optional. */
    }
    await favorites.initialize();
    await downloads.initialize();
    await updates.initialize();
    return AppDependencies(
      downloads: downloads,
      sources: sources,
      settings: settings,
      favorites: favorites,
      updates: updates,
      shares: ShareGateway(),
      parser: parser,
      migration: migration,
      prepareDownload: () async {
        // Notification permission is optional and never gates a file transfer.
        try {
          await callPlatform('requestNotifications', {});
        } on PlatformException {
          /* The download can still proceed. */
        }
      },
    );
  } catch (_) {
    updates.dispose();
    downloads.dispose();
    sources.dispose();
    settings.dispose();
    favorites.dispose();
    await backend.close();
    rethrow;
  }
}

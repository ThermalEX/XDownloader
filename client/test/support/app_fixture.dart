import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/bootstrap.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/core/models/source.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/post_link.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/platform/share_gateway.dart';

import 'fake_download_backend.dart';
import 'fake_update_backend.dart';

import 'package:xdownloader/data/repositories/update_repository.dart';

class MemorySnapshotStore extends SnapshotStore {
  MemorySnapshotStore() : super(Directory.systemTemp);
  final values = <String, String>{};
  @override
  Future<Map<String, Object?>> read(String key) async => values[key] == null
      ? {}
      : Map<String, Object?>.from(jsonDecode(values[key]!) as Map);
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    values[key] = jsonEncode(data);
  }
}

class UiDownloadBackend extends FakeDownloadBackend {
  UiDownloadBackend() : super(Directory.systemTemp);
  final opened = <SavedFile>[];
  final previewed = <SavedFile>[];
  Future<void> Function()? beforeReadable;
  @override
  Future<void> ensureReadable(SavedFile file) async {
    await beforeReadable?.call();
    if (!saved.values.any((saved) => saved.locator == file.locator)) {
      throw const AppFailure(FailureKind.fileMissing, '文件不存在或已被移走');
    }
    previewed.add(file);
  }

  @override
  Future<SavedFile> publish(String id) async => saved.putIfAbsent(id, () {
    publications++;
    return SavedFile(
      locator: 'content://xdl/test/$id',
      displayName: '$id.mp4',
      bytes: 8,
      mimeType: 'video/mp4',
    );
  });
  @override
  Future<void> open(SavedFile file) async {
    opened.add(file);
  }
}

class FixtureParser extends ParseClient {
  Future<MediaResult> Function(String, ParseCancellation)? respond;
  final calls = <String>[];
  @override
  Future<MediaResult> parse(
    String input, {
    required List<ParseSource> sources,
    required bool autoFallback,
    required ParseCancellation cancellation,
  }) async {
    calls.add(input);
    return respond == null
        ? resultFor(PostLink.tryParse(input)!.postId)
        : respond!(input, cancellation);
  }
}

MediaResult resultFor(String id) => MediaResult(
  PostLink(id, 'author', Uri.parse('https://x.com/author/status/$id')),
  '中文视频',
  '中文作者',
  null,
  const Duration(seconds: 12),
  [
    MediaItem(1, [
      MediaVariant(
        1,
        1280,
        720,
        Uri.parse('https://video.twimg.com/$id/1280x720/a.mp4'),
        2000,
        'mp4',
      ),
      MediaVariant(
        1,
        640,
        360,
        Uri.parse('https://video.twimg.com/$id/640x360/a.mp4'),
        256,
        'mp4',
      ),
    ]),
    MediaItem(2, [
      MediaVariant(
        2,
        720,
        1280,
        Uri.parse('https://video.twimg.com/$id/720x1280/b.mp4'),
        2000,
        'mp4',
      ),
    ]),
  ],
  'xdl',
);

class AppFixture {
  final store = MemorySnapshotStore();
  final backend = UiDownloadBackend();
  final parser = FixtureParser();
  final shareEvents = StreamController<Object?>.broadcast(sync: true);
  late final DownloadRepository downloads;
  late final SourceRepository sources;
  late final SettingsRepository settings;
  late final FavoriteRepository favorites;
  late final AppDependencies dependencies;
  late final UpdateRepository updates;
  final updateBackend = FakeUpdateBackend();
  final releaseClient = FixtureReleaseClient();
  String? clipboard;
  Future<String?> Function()? clipboardReader;
  int clipboardReads = 0;
  Future<void> initialize() async {
    downloads = DownloadRepository(store: store, backend: backend);
    sources = SourceRepository(store);
    settings = SettingsRepository(store);
    favorites = FavoriteRepository(store);
    await sources.initialize();
    await settings.initialize();
    await favorites.initialize();
    await downloads.initialize();
    updates = UpdateRepository(
      store: store,
      releases: releaseClient,
      backend: updateBackend,
    );
    await updates.initialize();
    await updates.setAutoCheck(false);
    await settings.edit((s) => s.copyWith(autoClipboard: false));
    dependencies = AppDependencies(
      downloads: downloads,
      sources: sources,
      settings: settings,
      favorites: favorites,
      shares: ShareGateway(
        call: (_, _) async => null,
        events: shareEvents.stream,
      ),
      parser: parser,
      updates: updates,
      readClipboard: () async {
        clipboardReads++;
        if (clipboardReader != null) return clipboardReader!();
        return clipboard;
      },
    );
  }

  Future<void> close() async {
    updates.dispose();
    downloads.dispose();
    sources.dispose();
    settings.dispose();
    favorites.dispose();
    await backend.close();
    await shareEvents.close();
  }
}

Future<void> withAppFixture(
  WidgetTester tester,
  Future<void> Function(AppFixture) body,
) async {
  // Queues and their futures must share the widget test's fake-async zone.
  final fixture = AppFixture();
  await fixture.initialize();
  try {
    await body(fixture);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.close();
  }
}

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:video_player/video_player.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/app/bootstrap.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/data/repositories/download_repository.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/data/repositories/favorite_repository.dart';
import 'package:xdownloader/data/repositories/source_repository.dart';
import 'package:xdownloader/data/storage/snapshot_store.dart';
import 'package:xdownloader/platform/android_download_backend.dart';
import 'package:xdownloader/platform/download_backend.dart';
import 'package:xdownloader/platform/platform_bridge.dart';
import 'package:xdownloader/platform/share_gateway.dart';
import 'package:xdownloader/data/repositories/update_repository.dart';

import '../test/support/fake_update_backend.dart';

const sample =
    'https://video.twimg.com/amplify_video/1655498815133335553/vid/320x568/hf7SEZqvRAUkWsTK.mp4?tag=16';
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('denied notifications still save, recover, and open real MP4', (
    tester,
  ) async {
    final enabled = await callPlatform('notificationStatus', {});
    expect(enabled, isA<bool>());
    if (const bool.fromEnvironment('expectNotificationsDenied')) {
      expect(enabled, isFalse);
    }
    // A killed earlier probe run may leave native fixture records; remove only test-owned files.
    for (final raw in await callPlatform('rawSnapshot', {}) as List) {
      final record = raw as Map;
      final request = record['request'] as Map?;
      if ((request?['displayName'] as String? ?? '').startsWith('xdl_probe_')) {
        await callPlatform('probeDelete', {'taskId': record['taskId']});
      }
    }
    final directory = Directory(
      '${await callPlatform('supportDirectory', {})}/flow_${newTaskId()}',
    );
    final store = SnapshotStore(directory);
    final backend = AndroidDownloadBackend();
    var downloads = DownloadRepository(store: store, backend: backend);
    final sources = SourceRepository(store),
        settings = SettingsRepository(store);
    final favorites = FavoriteRepository(store);
    final updates = UpdateRepository(
      store: store,
      releases: FixtureReleaseClient(),
      backend: FakeUpdateBackend(),
    );
    final owned = <String>[];
    await sources.initialize();
    await settings.initialize();
    await favorites.initialize();
    await downloads.initialize();
    await updates.initialize();
    await updates.setAutoCheck(false);
    await settings.edit((s) => s.copyWith(autoClipboard: false));
    final author = 'xdl_probe_${newTaskId().substring(0, 8)}';
    final parser = ParseClient(
      clientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'success': true,
              'title': '公开样例视频',
              'author': author,
              'videos': [
                for (final index in [1, 2])
                  {
                    'video_index': index,
                    'direct_download_url': '$sample&xdl_probe=$index',
                    'width': 320,
                    'quality': 568,
                  },
              ],
            }),
          ),
          200,
        ),
      ),
    );
    AppDependencies deps() => AppDependencies(
      downloads: downloads,
      sources: sources,
      settings: settings,
      favorites: favorites,
      updates: updates,
      parser: parser,
      shares: ShareGateway(),
      readClipboard: () async => null,
    );
    try {
      await tester.pumpWidget(XDownloaderApp(dependencies: deps()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://x.com/9GAG/status/1661175429859012608',
      );
      await tester.tap(find.bySemanticsLabel('解析链接'));
      await tester.pumpAndSettle();
      expect(find.text('视频 1'), findsOneWidget);
      expect(find.text('视频 2'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('favorite_current')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_current')));
      await tester.pumpAndSettle();
      expect(favorites.items.single.postId, '1661175429859012608');
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorite_1661175429859012608')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      final row = find.bySemanticsLabel('下载视频 1，320 × 568');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump(const Duration(seconds: 1));
      expect(downloads.records, hasLength(1));
      final id = downloads.records.single.taskId;
      owned.add(id);
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pump();
      for (
        var i = 0;
        i < 90 && downloads.records.single.phase != DownloadPhase.completed;
        i++
      ) {
        await tester.pump(const Duration(seconds: 1));
        await downloads.reconcile();
      }
      expect(downloads.records.single.phase, DownloadPhase.completed);
      final info = await callPlatform('probeInspect', {'taskId': id}) as Map;
      final data = base64Decode(info['data'] as String);
      expect(data.length, 354883);
      expect(
        sha256.convert(data).toString(),
        '3d9e9c81075a71574c4784ee4db6ddcad489d9a7071dd35986c1b58ca2287fa9',
      );
      expect(info['relativePath'], 'Download/XDownloader/');
      if (enabled == false) expect(info['savedNotification'], false);
      final receipt = downloads.records.single.savedFile!;
      final cover = await backend.thumbnailSavedFile(receipt);
      expect(cover, isNotNull);
      expect(cover!.length, greaterThan(100));
      expect(cover.take(2), [0xff, 0xd8]);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(PageView),
        Offset(-tester.getSize(find.byType(PageView)).width * .8, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(find.byKey(const Key('theme_mode')), findsNothing);
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      await tester.tap(find.text('规则设置'));
      await tester.pumpAndSettle();
      expect(find.text('下载源'), findsOneWidget);
      expect(find.text('失败后自动换源'), findsNothing);
      await tester.tap(find.text('下载源'));
      await tester.pumpAndSettle();
      expect(find.text('失败后自动换源'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.text('自动读取剪贴板'), findsNothing);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('应用设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用设置'));
      await tester.pumpAndSettle();
      expect(find.text('自动读取剪贴板'), findsOneWidget);
      expect(find.text('失败后自动换源'), findsNothing);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('外观设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观设置'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('theme_mode')), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(PageView),
        Offset(tester.getSize(find.byType(PageView)).width * .8, 0),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(PageView),
        Offset(tester.getSize(find.byType(PageView)).width * .8, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('download_$id')));
      await tester.pumpAndSettle();
      expect(find.text('隐私模式已启动，无法查看视频'), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      expect(find.text('隐私模式已启动，无法查看收藏'), findsOneWidget);
      expect(
        find.byKey(const Key('favorite_1661175429859012608')),
        findsNothing,
      );
      await settings.edit((s) => s.copyWith(privacyMode: false));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('favorite_1661175429859012608')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('download_$id')));
      for (
        var i = 0;
        i < 30 && find.byType(VideoPlayer).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(VideoPlayer), findsOneWidget);
      final player = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(player.value.isInitialized, isTrue);
      if (find.byType(Slider).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('player_gestures')));
        await tester.pump();
      }
      await tester.scrollUntilVisible(find.byType(Slider), 150);
      if (player.value.isPlaying) {
        await tester.tap(find.byTooltip('暂停'));
        await tester.pumpAndSettle();
      }
      expect(player.value.isPlaying, isFalse);
      var tapPoint =
          tester.getTopLeft(find.byKey(const Key('player_gestures'))) +
          const Offset(60, 45);
      await tester.tapAt(tapPoint);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(Slider), findsNothing);
      await tester.tapAt(tapPoint);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(Slider), findsOneWidget);
      await player.seekTo(Duration.zero);
      await player.play();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(Slider), findsNothing);
      await tester.tapAt(tapPoint);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(Slider), findsOneWidget);
      await player.pause();
      await tester.pump();
      await tester.tap(find.byType(Slider));
      await tester.pump(const Duration(seconds: 1));
      expect(player.value.position, greaterThan(Duration.zero));
      await tester.tap(find.byTooltip('播放速度'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1.5×'));
      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();
      expect(player.value.playbackSpeed, 1.5);
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      expect(
        (await callPlatform('readPlaybackControls', {}) as Map)['fullscreen'],
        isTrue,
      );
      await tester.tap(find.byTooltip('屏幕方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('横屏播放'));
      for (
        var i = 0;
        i < 20 &&
            tester.view.physicalSize.width < tester.view.physicalSize.height;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      expect(
        tester.view.physicalSize.width,
        greaterThan(tester.view.physicalSize.height),
      );
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(player),
      );
      await tester.tap(find.byTooltip('屏幕方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('竖屏播放'));
      for (
        var i = 0;
        i < 20 &&
            tester.view.physicalSize.width > tester.view.physicalSize.height;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      expect(
        tester.view.physicalSize.height,
        greaterThan(tester.view.physicalSize.width),
      );
      await tester.tap(find.byTooltip('屏幕方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      final surface = tester.getRect(find.byKey(const Key('player_gestures')));
      final point =
          surface.topLeft + Offset(surface.width * 0.4, surface.height * 0.2);
      await player.play();
      await tester.pump();
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(player.value.isPlaying, isFalse);
      await player.seekTo(Duration.zero);
      await tester.pump();
      await tester.dragFrom(point, Offset(surface.width * 0.3, 0));
      await tester.pumpAndSettle();
      expect(player.value.position, greaterThan(Duration.zero));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('视频预览'), findsOneWidget);
      expect(
        (await callPlatform('readPlaybackControls', {}) as Map)['fullscreen'],
        isFalse,
      );
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(Key('download_$id')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      await tester.drag(
        find.byType(PageView),
        Offset(-tester.getSize(find.byType(PageView)).width * .8, 0),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(PageView),
        Offset(tester.getSize(find.byType(PageView)).width * .8, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      downloads.dispose();
      downloads = DownloadRepository(store: store, backend: backend);
      await downloads.initialize();
      expect(downloads.records.single.savedFile!.locator, receipt.locator);
      expect((await downloads.fileForPreview(id)).locator, receipt.locator);
      final cancelId = newTaskId();
      owned.add(cancelId);
      await downloads.start(
        DownloadRequest(
          taskId: cancelId,
          url: Uri.parse('$sample&cancel=$cancelId'),
          displayName: 'xdl_probe_$cancelId.mp4',
          headers: const {},
          mediaIndex: 1,
        ),
      );
      await downloads.cancel(cancelId);
      expect(downloads.records.first.phase, DownloadPhase.cancelled);
      final retry = await downloads.retry(cancelId);
      owned.add(retry);
      expect(retry, isNot(cancelId));
      await downloads.cancel(retry);
      await downloads.deleteFile(id);
      expect(downloads.history.any((entry) => entry.taskId == id), isTrue);
      await tester.pumpWidget(XDownloaderApp(dependencies: deps()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_downloads')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download_history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('history_$id')));
      await tester.pumpAndSettle();
      expect(find.text('下载历史'), findsNothing);
      expect(find.byKey(const Key('nav_home')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      downloads.dispose();
      sources.dispose();
      settings.dispose();
      favorites.dispose();
      updates.dispose();
      await backend.close();
      for (final id in owned) {
        await callPlatform('probeDelete', {'taskId': id});
      }
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
}

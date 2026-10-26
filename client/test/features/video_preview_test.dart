import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/app/handed_layout.dart';
import 'package:xdownloader/features/downloads/video_preview_screen.dart';
import 'package:xdownloader/features/downloads/video_thumbnail.dart';
import 'package:xdownloader/platform/platform_bridge.dart';

import '../support/fake_video_platform.dart';

void main() {
  const file = SavedFile(
    locator: 'content://media/external/downloads/123',
    displayName: '示例视频.mp4',
    bytes: 8,
    mimeType: 'video/mp4',
  );
  late FakeVideoPlatform platform;
  late VideoPlayerPlatform previous;
  final deviceCalls = <MethodCall>[];
  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    deviceCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
          deviceCalls.add(call);
          if (call.method == 'beginPlaybackControls' ||
              call.method == 'readPlaybackControls') {
            return {'brightness': 0.5, 'volume': 0.5, 'volumeFixed': false};
          }
          return (call.arguments as Map?)?['value'];
        });
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });
  Future<void> preview(WidgetTester tester, {bool leftHanded = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => HandedLayout(
          handedness: leftHanded ? Handedness.left : Handedness.right,
          child: child!,
        ),
        home: VideoPreviewScreen(file: file, onOpenExternal: () async {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'left-hand player groups actions left while keeping timeline direction',
    (tester) async {
      await preview(tester, leftHanded: true);
      final time = find.textContaining(' / ');
      expect(
        tester.getCenter(find.byTooltip('全屏')).dx,
        lessThan(tester.getCenter(time).dx),
      );
      expect(
        Directionality.of(tester.element(find.byType(Slider))),
        TextDirection.ltr,
      );
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byTooltip('返回')).right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('屏幕方向').last).left),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('single tap hides and reveals paused controls', (tester) async {
    await preview(tester);
    await tester.tap(find.byTooltip('暂停'));
    await tester.pumpAndSettle();
    final point =
        tester.getTopLeft(find.byKey(const Key('player_gestures'))) +
        const Offset(100, 30);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(Slider), findsNothing);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(Slider), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('late playback hides controls and single tap resets hide timer', (
    tester,
  ) async {
    await preview(tester);
    await tester.tap(find.byTooltip('暂停'));
    await tester.pumpAndSettle();
    final player = tester
        .widget<VideoPlayer>(find.byType(VideoPlayer))
        .controller;
    await player.play();
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(Slider), findsNothing);
    final point =
        tester.getTopLeft(find.byKey(const Key('player_gestures'))) +
        const Offset(100, 30);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(Slider), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(Slider), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(Slider), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('portrait controls fit 320dp and doubled text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      platform.size = const Size(320, 568);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: VideoPreviewScreen(file: file, onOpenExternal: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('全屏').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('退出全屏').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });
  }

  testWidgets(
    'portrait fullscreen follows system and direction menu can request landscape or restore system',
    (tester) async {
      final chrome = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            chrome.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      platform.size = const Size(320, 568);
      await preview(tester);
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      MethodCall orientation() => chrome.lastWhere(
        (c) => c.method == 'SystemChrome.setPreferredOrientations',
      );
      expect(orientation().arguments, isEmpty);
      await tester.tap(find.byTooltip('屏幕方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('横屏播放'));
      await tester.pumpAndSettle();
      expect(orientation().arguments, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(platform.sources, hasLength(1));
      await tester.tap(find.byTooltip('屏幕方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统'));
      await tester.pumpAndSettle();
      expect(orientation().arguments, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(orientation().arguments, isEmpty);
    },
  );
  testWidgets(
    'vertical gestures wait for fresh hardware volume before applying accumulated movement',
    (tester) async {
      await preview(tester);
      final fresh = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platformChannel, (call) async {
            deviceCalls.add(call);
            if (call.method == 'readPlaybackControls') return fresh.future;
            return (call.arguments as Map?)?['value'];
          });
      final rect = tester.getRect(find.byKey(const Key('player_gestures')));
      final gesture = await tester.startGesture(
        rect.topRight + const Offset(-60, 70),
      );
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump();
      expect(
        deviceCalls.where((c) => c.method == 'setPlaybackVolume'),
        isEmpty,
      );
      fresh.complete({'brightness': 0.5, 'volume': 0.1, 'volumeFixed': false});
      await tester.pump();
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final changes = deviceCalls.where((c) => c.method == 'setPlaybackVolume');
      expect(changes, isNotEmpty);
      expect(changes.every((c) => c.arguments['value'] < 0.4), isTrue);
    },
  );
  testWidgets('edge-to-edge restoration follows Chewie fullscreen cleanup', (
    tester,
  ) async {
    final chrome = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          chrome.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await preview(tester);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      chrome
          .lastWhere(
            (c) => c.method.startsWith('SystemChrome.setEnabledSystemUI'),
          )
          .arguments,
      'SystemUiMode.edgeToEdge',
    );
  });
  testWidgets(
    'Chewie gestures use double tap for pause and horizontal swipe for seek',
    (tester) async {
      await preview(tester);
      expect(find.byType(Chewie), findsOneWidget);
      final surface = find.byKey(const Key('player_gestures'));
      final point = tester.getTopLeft(surface) + const Offset(100, 30);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(
        platform.calls.lastWhere((c) => c == 'play' || c == 'pause'),
        'pause',
      );
      expect(platform.calls.where((c) => c.startsWith('seek:')), isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(
        platform.calls.lastWhere((c) => c == 'play' || c == 'pause'),
        'play',
      );
      await tester.dragFrom(point, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(platform.calls.where((c) => c.startsWith('seek:')), isNotEmpty);
      expect(
        deviceCalls.where(
          (c) =>
              c.method == 'setPlaybackBrightness' ||
              c.method == 'setPlaybackVolume',
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'left and right vertical swipes adjust brightness and volume, exit restores window',
    (tester) async {
      await preview(tester);
      final rect = tester.getRect(find.byKey(const Key('player_gestures')));
      await tester.dragFrom(
        rect.topLeft + const Offset(60, 70),
        const Offset(0, -45),
      );
      await tester.pumpAndSettle();
      expect(
        deviceCalls.where((c) => c.method == 'setPlaybackBrightness'),
        isNotEmpty,
      );
      expect(
        deviceCalls.where((c) => c.method == 'setPlaybackVolume'),
        isEmpty,
      );
      await tester.dragFrom(
        rect.topRight + const Offset(-60, 70),
        const Offset(0, -45),
      );
      await tester.pumpAndSettle();
      expect(
        deviceCalls.where((c) => c.method == 'setPlaybackVolume'),
        isNotEmpty,
      );
      expect(platform.calls.where((c) => c.startsWith('seek:')), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(deviceCalls.last.method, 'endPlaybackControls');
    },
  );

  testWidgets(
    'speed selection and full screen reuse the player and back restores bars',
    (tester) async {
      await preview(tester);
      await tester.tap(find.byTooltip('播放速度'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1.5×'));
      await tester.tap(find.text('1.5×'));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('speed:1.5'));
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      expect(platform.sources, hasLength(1));
      expect(
        deviceCalls.any(
          (c) =>
              c.method == 'setPlaybackFullscreen' &&
              c.arguments['value'] == true,
        ),
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('视频预览'), findsOneWidget);
      expect(find.byTooltip('全屏'), findsOneWidget);
      expect(platform.calls, isNot(contains('dispose')));
      expect(
        deviceCalls.any(
          (c) =>
              c.method == 'setPlaybackFullscreen' &&
              c.arguments['value'] == false,
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'local preview plays the saved content URI, pauses and disposes',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPreviewScreen(file: file, onOpenExternal: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(platform.sources.single.uri, file.locator);
      expect(platform.sources.single.sourceType, DataSourceType.contentUri);
      expect(platform.calls, contains('play'));
      await tester.scrollUntilVisible(find.byTooltip('暂停'), 120);
      await tester.tap(find.byTooltip('暂停'));
      await tester.pumpAndSettle();
      expect(platform.calls, contains('pause'));
      expect(find.byTooltip('播放'), findsOneWidget);
      final state = tester.state(find.byType(VideoPreviewScreen));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(state.mounted, isFalse);
      expect(platform.calls, contains('dispose'));
    },
  );
  testWidgets(
    'decoder errors offer an external player without exposing raw details',
    (tester) async {
      platform.fail = true;
      var external = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPreviewScreen(
            file: file,
            onOpenExternal: () async {
              external++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('无法播放此视频'), findsOneWidget);
      expect(find.textContaining('private decoder'), findsNothing);
      await tester.tap(find.text('使用系统播放器'));
      await tester.pumpAndSettle();
      expect(external, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'thumbnail renders image data once and falls back when unavailable',
    (tester) async {
      var calls = 0;
      final data = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      Future<Uint8List?> load() async {
        calls++;
        return data;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoThumbnail(locator: file.locator, load: load),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoThumbnail(locator: file.locator, load: load),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoThumbnail(locator: 'missing', load: () async => null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    },
  );
}

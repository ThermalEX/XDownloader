import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../../app/app_shell.dart';
import '../../core/models/download.dart';
import '../../platform/player_device_controls.dart';
import 'material_player_controls.dart';
import 'player_orientation_button.dart';

class VideoPreviewScreen extends StatefulWidget {
  const VideoPreviewScreen({
    super.key,
    required this.file,
    required this.onOpenExternal,
    this.title,
  });
  final SavedFile file;
  final String? title;
  final Future<void> Function() onOpenExternal;
  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  late final VideoPlayerController _player;
  final _device = PlayerDeviceControls();
  ChewieController? _chewie;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    final uri = Uri.parse(widget.file.locator);
    _player = uri.scheme == 'content'
        ? VideoPlayerController.contentUri(uri)
        : VideoPlayerController.file(
            uri.scheme == 'file'
                ? File.fromUri(uri)
                : File(widget.file.locator),
          );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _player.initialize();
      if (!mounted) return;
      try {
        await _device.begin();
      } catch (_) {
        /* Playback remains available without device controls. */
      }
      if (!mounted) return;
      _chewie = ChewieController(
        videoPlayerController: _player,
        customControls: MaterialPlayerControls(
          player: _player,
          device: _device,
        ),
        playbackSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
        allowDoubleTapSeek: false,
        swipeToExitFullscreen: false,
        deviceOrientationsOnEnterFullScreen: const [],
        deviceOrientationsAfterFullScreen: const [],
      )..addListener(_fullscreenChanged);
      setState(() {});
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _fullscreenChanged() {
    unawaited(
      _device
          .fullscreen(_chewie?.isFullScreen == true)
          .catchError((Object _) {}),
    );
    if (_chewie?.isFullScreen != true) {
      // Chewie restores manual overlays after notifying its listeners.
      scheduleMicrotask(() {
        if (mounted && _chewie?.isFullScreen != true) {
          unawaited(
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _chewie?.removeListener(_fullscreenChanged);
    _chewie?.dispose();
    unawaited(_device.end().catchError((Object _) {}));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('视频预览'),
      actions: [
        PlayerOrientationButton(controller: _chewie),
        IconButton(
          tooltip: '使用系统播放器',
          onPressed: () => runAction(context, widget.onOpenExternal),
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _player,
              builder: (context, value, _) {
                if (_failed || value.hasError) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_outlined, size: 48),
                          const SizedBox(height: 16),
                          const Text('无法播放此视频'),
                          const SizedBox(height: 8),
                          const Text(
                            '文件可能已被移走，或此设备暂不支持该视频格式。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () =>
                                runAction(context, widget.onOpenExternal),
                            child: const Text('使用系统播放器'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!value.isInitialized || _chewie == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.title ?? widget.file.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: ColoredBox(
                        color: Colors.black,
                        child: SizedBox(
                          height:
                              ((constraints.maxWidth - 32) / value.aspectRatio)
                                  .clamp(1.0, constraints.maxHeight * 0.55),
                          child: Chewie(controller: _chewie!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('单击显隐控制栏，双击暂停或继续；左右滑动调进度，左侧上下调亮度，右侧上下调音量。'),
                  ],
                );
              },
            ),
      ),
    ),
  );
}

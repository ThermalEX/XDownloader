import 'dart:async';
import 'dart:math' as math;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/handed_layout.dart';
import '../../app/app_shell.dart';
import '../../platform/player_device_controls.dart';
import 'player_orientation_button.dart';

String playbackTime(Duration value) {
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  if (value.inHours == 0) return '${value.inMinutes}:$seconds';
  return '${value.inHours}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:$seconds';
}

class MaterialPlayerControls extends StatefulWidget {
  const MaterialPlayerControls({
    super.key,
    required this.player,
    required this.device,
  });
  final VideoPlayerController player;
  final PlayerDeviceControls device;
  @override
  State<MaterialPlayerControls> createState() => _MaterialPlayerControlsState();
}

class _MaterialPlayerControlsState extends State<MaterialPlayerControls> {
  bool _visible = true, _brightness = true;
  Timer? _hide;
  double? _seek;
  double _drag = 0, _origin = 0;
  String? _hint;
  int _gesture = 0;
  bool _levelReady = false, _levelDragging = false;
  late bool _playing;
  ChewieController get chewie => ChewieController.of(context);
  VideoPlayerController get player => widget.player;

  @override
  void initState() {
    super.initState();
    _playing = player.value.isPlaying;
    player.addListener(_playbackChanged);
    _scheduleHide();
  }

  void _playbackChanged() {
    final playing = player.value.isPlaying;
    if (playing == _playing) return;
    _playing = playing;
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!mounted || !_visible || !player.value.isPlaying) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && player.value.isPlaying && _seek == null && _hint == null) {
        setState(() => _visible = false);
      }
    });
  }

  Future<void> _toggle() => runAction(context, () async {
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      if (player.value.position >= player.value.duration) {
        await player.seekTo(Duration.zero);
      }
      await player.play();
    }
    if (mounted) setState(() => _visible = true);
    _scheduleHide();
  });

  void _startSeek() {
    _hide?.cancel();
    _gesture++;
    _levelDragging = false;
    _drag = 0;
    _origin = player.value.position.inMilliseconds.toDouble();
    setState(() => _seek = _origin);
  }

  Future<void> _finishSeek() async {
    final seek = _seek;
    if (seek != null) {
      await runAction(
        context,
        () => player.seekTo(Duration(milliseconds: seek.round())),
      );
    }
    if (!mounted) return;
    setState(() {
      _seek = null;
      _hint = null;
    });
    _scheduleHide();
  }

  Future<void> _startLevel(DragStartDetails details, double width) async {
    _hide?.cancel();
    final token = ++_gesture;
    _brightness = details.localPosition.dx < width / 2;
    _drag = 0;
    _levelReady = false;
    _levelDragging = true;
    try {
      await widget.device.refresh();
    } catch (_) {
      if (mounted && token == _gesture && _levelDragging) {
        setState(() => _hint = '暂时无法读取${_brightness ? '亮度' : '音量'}');
      }
      return;
    }
    if (!mounted || token != _gesture) return;
    _origin = _brightness ? widget.device.brightness : widget.device.volume;
    _levelReady = true;
    if (_drag != 0) await _applyLevel(token);
  }

  Future<void> _level(DragUpdateDetails details, double height) async {
    _drag -= details.delta.dy / math.max(height, 1);
    if (_levelReady) await _applyLevel(_gesture);
  }

  Future<void> _applyLevel(int token) async {
    final isBrightness = _brightness;
    try {
      final actual = await widget.device.adjust(isBrightness, _origin + _drag);
      if (!mounted || token != _gesture || !_levelDragging) return;
      setState(
        () => _hint = !isBrightness && widget.device.volumeFixed
            ? '此设备音量由外部控制'
            : '${isBrightness ? '亮度' : '音量'} ${(actual * 100).round()}%',
      );
    } catch (_) {
      if (mounted && token == _gesture && _levelDragging) {
        setState(() => _hint = '暂时无法调整${isBrightness ? '亮度' : '音量'}');
      }
    }
  }

  void _endLevel({bool cancelled = false}) {
    if (cancelled) _gesture++;
    _levelDragging = false;
    setState(() => _hint = null);
    _scheduleHide();
  }

  Future<void> _speed() async {
    _hide?.cancel();
    final speed = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('播放速度', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final speed in chewie.playbackSpeeds)
                ListTile(
                  title: Text('$speed×'),
                  selected: player.value.playbackSpeed == speed,
                  trailing: player.value.playbackSpeed == speed
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, speed),
                ),
            ],
          ),
        ),
      ),
    );
    if (speed != null && mounted) {
      await runAction(context, () => player.setPlaybackSpeed(speed));
    }
    _scheduleHide();
  }

  @override
  void dispose() {
    player.removeListener(_playbackChanged);
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: player,
    builder: (context, value, _) => LayoutBuilder(
      builder: (context, constraints) {
        final duration = value.duration.inMilliseconds.toDouble();
        final position = (_seek ?? value.position.inMilliseconds.toDouble())
            .clamp(0.0, math.max(duration, 1.0))
            .toDouble();
        final show = _visible;
        final leftHanded = HandedLayout.isLeft(context);
        final timeline = Expanded(
          child: Text(
            '${playbackTime(Duration(milliseconds: position.round()))} / ${playbackTime(value.duration)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: '视频画面，双击暂停或继续，左右滑动调整进度，左侧上下调亮度，右侧上下调音量',
                child: GestureDetector(
                  key: const Key('player_gestures'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _visible = !_visible);
                    _scheduleHide();
                  },
                  onDoubleTap: _toggle,
                  onHorizontalDragStart: (_) => _startSeek(),
                  onHorizontalDragUpdate: (details) {
                    _drag += details.delta.dx;
                    final span = math.min(duration, 120000.0);
                    setState(() {
                      _seek =
                          (_origin +
                                  _drag /
                                      math.max(constraints.maxWidth, 1) *
                                      span)
                              .clamp(0.0, duration);
                      _hint =
                          '${playbackTime(Duration(milliseconds: _seek!.round()))} / ${playbackTime(value.duration)}';
                    });
                  },
                  onHorizontalDragEnd: (_) => _finishSeek(),
                  onHorizontalDragCancel: () {
                    setState(() {
                      _seek = null;
                      _hint = null;
                    });
                    _scheduleHide();
                  },
                  onVerticalDragStart: (details) =>
                      _startLevel(details, constraints.maxWidth),
                  onVerticalDragUpdate: (details) =>
                      _level(details, constraints.maxHeight),
                  onVerticalDragEnd: (_) => _endLevel(),
                  onVerticalDragCancel: () => _endLevel(cancelled: true),
                ),
              ),
            ),
            if (value.isBuffering)
              const Center(child: CircularProgressIndicator()),
            if (_hint != null)
              Center(
                child: IgnorePointer(
                  child: Material(
                    borderRadius: BorderRadius.circular(20),
                    color: Theme.of(context).colorScheme.inverseSurface,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _hint!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (show)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: SafeArea(
                  top: false,
                  bottom: chewie.isFullScreen,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh
                        .withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Slider(
                            value: position,
                            max: math.max(duration, 1.0),
                            semanticFormatterCallback: (v) =>
                                playbackTime(Duration(milliseconds: v.round())),
                            onChangeStart: (_) => _startSeek(),
                            onChanged: duration <= 0
                                ? null
                                : (v) => setState(() => _seek = v),
                            onChangeEnd: (_) => _finishSeek(),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: value.isPlaying ? '暂停' : '播放',
                                onPressed: _toggle,
                                icon: Icon(
                                  value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                              if (!leftHanded) timeline,
                              TextButton(
                                onPressed: _speed,
                                child: Tooltip(
                                  message: '播放速度',
                                  child: Text('${value.playbackSpeed}×'),
                                ),
                              ),
                              IconButton(
                                tooltip: chewie.isFullScreen ? '退出全屏' : '全屏',
                                onPressed: chewie.toggleFullScreen,
                                icon: Icon(
                                  chewie.isFullScreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                ),
                              ),
                              if (leftHanded) timeline,
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (show && chewie.isFullScreen)
              Positioned(
                top: 8,
                left: leftHanded ? 64 : null,
                right: leftHanded ? null : 8,
                child: SafeArea(
                  child: PlayerOrientationButton(
                    controller: chewie,
                    tonal: true,
                  ),
                ),
              ),
            if (show && chewie.isFullScreen)
              Positioned(
                top: 8,
                left: 8,
                child: SafeArea(
                  child: IconButton.filledTonal(
                    tooltip: '返回',
                    onPressed: chewie.exitFullScreen,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

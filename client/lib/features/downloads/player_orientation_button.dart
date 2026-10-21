import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlayerOrientationButton extends StatelessWidget {
  const PlayerOrientationButton({
    super.key,
    this.controller,
    this.tonal = false,
  });

  final ChewieController? controller;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final menu = PopupMenuButton<List<DeviceOrientation>>(
      tooltip: '屏幕方向',
      enabled: controller != null,
      icon: const Icon(Icons.screen_rotation),
      onSelected: (orientations) async {
        if (orientations.isNotEmpty && controller?.isFullScreen == false) {
          controller!.enterFullScreen();
          // Let Chewie finish its fullscreen entry orientation request first.
          await WidgetsBinding.instance.endOfFrame;
        }
        if (context.mounted) {
          await SystemChrome.setPreferredOrientations(orientations);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          child: Text('横屏播放'),
        ),
        PopupMenuItem(
          value: [DeviceOrientation.portraitUp],
          child: Text('竖屏播放'),
        ),
        PopupMenuItem(value: [], child: Text('跟随系统')),
      ],
    );
    if (!tonal) return menu;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconTheme(
        data: IconThemeData(
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
        child: menu,
      ),
    );
  }
}

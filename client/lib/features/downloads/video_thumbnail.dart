import 'dart:typed_data';

import 'package:flutter/material.dart';

class VideoThumbnail extends StatefulWidget {
  const VideoThumbnail({super.key, required this.locator, required this.load});
  final String locator;
  final Future<Uint8List?> Function() load;
  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  late Future<Uint8List?> _image = _load();
  Future<Uint8List?> _load() async {
    try {
      return await widget.load();
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locator != widget.locator) _image = _load();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 64,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: FutureBuilder<Uint8List?>(
          future: _image,
          builder: (context, snapshot) {
            final data = snapshot.data;
            const fallback = Center(child: Icon(Icons.videocam_outlined));
            return data == null
                ? fallback
                : Image.memory(
                    data,
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => fallback,
                  );
          },
        ),
      ),
    ),
  );
}

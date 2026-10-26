import 'package:flutter/material.dart';

import 'dart:typed_data';
import 'dart:ui';

import 'video_thumbnail.dart';

import '../../app/handed_layout.dart';
import '../../core/models/download.dart';
import '../../core/models/app_failure.dart';

class DownloadTile extends StatelessWidget {
  const DownloadTile({
    super.key,
    required this.record,
    required this.onOpen,
    required this.onCancel,
    required this.onRetry,
    this.onActions,
    this.onSelect,
    this.selected = false,
    this.selectionMode = false,
    this.loadThumbnail,
    this.privacyMode = false,
  });
  final DownloadRecord record;
  final VoidCallback onOpen, onCancel, onRetry;
  final VoidCallback? onActions;
  final VoidCallback? onSelect;
  final bool selected, selectionMode;
  final bool privacyMode;
  final Future<Uint8List?> Function()? loadThumbnail;
  String bytes(int n) => n >= 1048576
      ? '${(n / 1048576).toStringAsFixed(1)} MB'
      : '${(n / 1024).toStringAsFixed(0)} KB';
  @override
  Widget build(BuildContext context) {
    final r = record;
    Widget privateView(Widget child, {String? label}) => !privacyMode
        ? child
        : Semantics(
            label: label,
            excludeSemantics: true,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: child,
            ),
          );
    final label = switch (r.phase) {
      DownloadPhase.queued => '等待下载',
      DownloadPhase.running => '下载中',
      DownloadPhase.publishing => '正在保存到下载文件夹',
      DownloadPhase.completed =>
        r.error?.kind == FailureKind.fileMissing
            ? '文件已不存在'
            : r.legacy && r.savedFile == null
            ? '旧记录 · 无法定位文件'
            : '已保存',
      DownloadPhase.failed => '下载失败',
      DownloadPhase.cancelled => '已取消',
    };
    final mirror = HandedLayout.isLeft(context) && !selectionMode;
    final preview = selectionMode && r.phase.terminal
        ? Checkbox(
            value: selected,
            onChanged: onSelect == null ? null : (_) => onSelect!(),
          )
        : (r.savedFile != null || r.request.coverUrl != null) &&
              loadThumbnail != null
        ? privateView(
            VideoThumbnail(
              locator: r.savedFile?.locator ?? r.request.coverUrl.toString(),
              load: loadThumbnail!,
            ),
          )
        : null;
    final controls = !selectionMode && r.phase.terminal && onActions != null
        ? IconButton(
            tooltip: '下载操作',
            onPressed: onActions,
            icon: const Icon(Icons.more_vert),
          )
        : null;
    return Card.filled(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: Key('download_${r.taskId}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: privateView(
              Text(
                r.request.displayName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              label: '已隐藏的视频名称',
            ),
            subtitle: Text(label),
            selected: selected,
            selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
            leading: mirror ? controls : preview,
            onTap: selectionMode && r.phase.terminal
                ? onSelect
                : r.phase == DownloadPhase.completed &&
                      r.error?.kind != FailureKind.fileMissing
                ? onOpen
                : null,
            onLongPress: r.phase.terminal ? onSelect ?? onActions : null,
            trailing: mirror ? preview : controls,
          ),
          if (r.phase == DownloadPhase.running) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: (r.totalBytes ?? 0) > 0
                    ? (r.bytes / r.totalBytes!).clamp(0, 1)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${bytes(r.bytes)}${r.totalBytes == null ? '' : ' / ${bytes(r.totalBytes!)}'}',
              ),
            ),
          ],
          if (r.error != null && r.error!.kind != FailureKind.fileMissing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                r.error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!r.phase.terminal ||
              r.phase == DownloadPhase.failed ||
              r.phase == DownloadPhase.cancelled)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 8,
                children: [
                  if (!r.phase.terminal)
                    TextButton(
                      key: Key('cancel_${r.taskId}'),
                      onPressed: onCancel,
                      child: const Text('取消'),
                    ),
                  if (r.phase == DownloadPhase.failed ||
                      r.phase == DownloadPhase.cancelled ||
                      r.phase == DownloadPhase.publishing && r.error != null)
                    TextButton(
                      key: Key('retry_${r.taskId}'),
                      onPressed: onRetry,
                      child: const Text('重试'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

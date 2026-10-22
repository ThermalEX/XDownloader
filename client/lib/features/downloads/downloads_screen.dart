import 'package:flutter/material.dart';

import '../../data/repositories/download_repository.dart';
import '../../data/repositories/favorite_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../core/models/app_failure.dart';
import '../../app/app_shell.dart';
import '../../app/library_search.dart';
import '../../core/models/download.dart';
import 'download_tile.dart';
import 'video_preview_screen.dart';
import 'download_history_screen.dart';

enum _DownloadAction { open, favorite, remove, delete }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.favorites,
    required this.onParse,
  });
  final DownloadRepository repository;
  final SettingsRepository settings;
  final FavoriteRepository favorites;
  final ValueChanged<String> onParse;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadRepository get repository => widget.repository;
  late final _search = LibrarySearch(
    widget.settings,
    onChanged: _selected.clear,
  );
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DownloadRecord> get _visible {
    if (_search.isEmpty) return repository.records;
    final originalLinks = {
      for (final entry in repository.history) entry.taskId: entry.postUrl,
    };
    return repository.records
        .where(
          (record) => _search.matches([
            record.request.displayName,
            record.request.postUrl,
            originalLinks[record.taskId],
          ]),
        )
        .toList();
  }

  final _selected = <String>{};
  bool _busy = false;
  bool get _private => widget.settings.value.privacyMode;
  void _checkPrivacy() {
    if (_private) {
      throw const AppFailure(FailureKind.cancelled, '隐私模式已启动，无法查看视频');
    }
  }

  Future<void> _openExternal(DownloadRecord record) async {
    _checkPrivacy();
    await repository.open(record.taskId, beforeOpen: _checkPrivacy);
  }

  Future<void> _preview(BuildContext context, DownloadRecord record) =>
      runAction(context, () async {
        _checkPrivacy();
        final file = await repository.fileForPreview(record.taskId);
        _checkPrivacy();
        if (!context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => VideoPreviewScreen(
              file: file,
              title: record.request.displayName,
              onOpenExternal: () => _openExternal(record),
            ),
          ),
        );
      });
  void _select(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Future<void> _favorite(List<DownloadRecord> records) async {
    if (_busy) return;
    setState(() => _busy = true);
    var added = 0, existing = 0, missing = 0, failed = 0;
    try {
      for (final record in records) {
        if (_private) {
          throw const AppFailure(FailureKind.cancelled, '隐私模式已启动，无法添加收藏');
        }
        final source = repository.sourceForFavorite(record.taskId);
        if (source == null) {
          missing++;
          continue;
        }
        try {
          if (await widget.favorites.add(
            source.url.toString(),
            title: source.title,
          )) {
            added++;
          } else {
            existing++;
          }
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            [
              '已添加 $added 项收藏',
              if (existing > 0) '$existing 项已收藏',
              if (missing > 0) '$missing 项无原链接',
              if (failed > 0) '$failed 项保存失败',
            ].join('，'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batch(
    BuildContext context,
    List<DownloadRecord> records, {
    required bool delete,
  }) async {
    if (delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('删除 ${records.length} 个下载文件？'),
          content: const Text('将从设备中删除所选视频，并移除对应下载记录。下载历史仍会保留。此操作无法撤销。'),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除文件'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted || !context.mounted) return;
    setState(() => _busy = true);
    final failed = <String>{};
    for (final record in records) {
      try {
        if (delete) {
          await repository.deleteFile(record.taskId);
        } else {
          await repository.removeRecord(record.taskId);
        }
      } catch (_) {
        failed.add(record.taskId);
      }
    }
    if (!mounted || !context.mounted) return;
    setState(() {
      _busy = false;
      _selected
        ..clear()
        ..addAll(failed);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已${delete ? '删除' : '移除'} ${records.length - failed.length} 项${failed.isEmpty ? '' : '，${failed.length} 项未能完成，已保留记录'}',
        ),
      ),
    );
  }

  Widget _actionContent(IconData icon, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon),
      const SizedBox(height: 6),
      Text(label, textAlign: TextAlign.center),
    ],
  );

  Widget _selectionBar(
    BuildContext context,
    List<DownloadRecord> selected,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            if (_busy)
              const LinearProgressIndicator()
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        key: const Key('downloads_favorite_selected'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed:
                            !_private &&
                                selected.isNotEmpty &&
                                selected.every(
                                  (r) => r.phase == DownloadPhase.completed,
                                )
                            ? () =>
                                  runAction(context, () => _favorite(selected))
                            : null,
                        child: _actionContent(Icons.favorite_border, '添加收藏'),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Tooltip(
                        message: '删除所选文件',
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                          onPressed:
                              selected.isNotEmpty &&
                                  selected.every(
                                    (r) =>
                                        r.savedFile != null &&
                                        r.phase == DownloadPhase.completed,
                                  )
                              ? () => _batch(context, selected, delete: true)
                              : null,
                          child: _actionContent(Icons.delete_outline, '删除文件'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                        ),
                        onPressed: selected.isEmpty
                            ? null
                            : () => _batch(context, selected, delete: false),
                        child: _actionContent(Icons.playlist_remove, '移除记录'),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                IconButton(
                  tooltip: '退出多选',
                  onPressed: _busy ? null : () => setState(_selected.clear),
                  icon: const Icon(Icons.close),
                ),
                Expanded(child: Text('已选 ${selected.length} 项')),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _selected.addAll(
                            _visible
                                .where((r) => r.phase.terminal)
                                .map((r) => r.taskId),
                          );
                        }),
                  child: const Text('全选'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _actions(BuildContext context, DownloadRecord record) async {
    final action = await showModalBottomSheet<_DownloadAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: widget.settings,
        builder: (sheetContext, _) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    _private ? '已隐藏的视频' : record.request.displayName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),

                if (record.phase == DownloadPhase.completed)
                  ListTile(
                    leading: const Icon(Icons.favorite_border),
                    title: const Text('添加收藏'),
                    subtitle:
                        repository.sourceForFavorite(record.taskId) == null
                        ? const Text('无原链接，无法添加收藏')
                        : null,
                    enabled:
                        !_private &&
                        repository.sourceForFavorite(record.taskId) != null,
                    onTap: () =>
                        Navigator.pop(sheetContext, _DownloadAction.favorite),
                  ),
                if (record.savedFile != null) ...[
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('打开文件'),
                    onTap: () =>
                        Navigator.pop(sheetContext, _DownloadAction.open),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('删除文件'),
                    subtitle: const Text('删除设备中的视频，保留下载历史'),
                    onTap: () =>
                        Navigator.pop(sheetContext, _DownloadAction.delete),
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.playlist_remove),
                  title: const Text('移除记录'),
                  subtitle: const Text('保留视频文件和下载历史'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _DownloadAction.remove),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _DownloadAction.favorite:
        await runAction(context, () => _favorite([record]));
      case _DownloadAction.open:
        await runAction(context, () => _openExternal(record));
      case _DownloadAction.remove:
        await runAction(context, () => repository.removeRecord(record.taskId));
      case _DownloadAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除下载文件？'),
            content: Text(
              _private
                  ? '将从设备中删除所选视频，并移除下载列表条目，保留下载历史。'
                  : '将从设备中删除“${record.request.displayName}”，并移除下载列表条目，保留下载历史。',
            ),
            scrollable: true,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除文件'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await runAction(context, () => repository.deleteFile(record.taskId));
        }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([repository, widget.settings, _search]),
    builder: (context, _) {
      final visible = _visible;
      final selected = visible
          .where((r) => r.phase.terminal && _selected.contains(r.taskId))
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_private) LibrarySearchField(search: _search, name: 'downloads'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('download_history'),
                icon: const Icon(Icons.history),
                label: const Text('下载历史'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DownloadHistoryScreen(
                      repository: repository,
                      settings: widget.settings,
                      onParse: widget.onParse,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(indent: 20, endIndent: 20, height: 12),
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _selectionBar(context, selected),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: repository.reconcile,
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 1 + (visible.isEmpty ? 1 : visible.length),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return repository.storageFailure == null
                        ? const SizedBox.shrink()
                        : Text(repository.storageFailure!.message);
                  }
                  if (visible.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Column(
                        children: [
                          Icon(Icons.download_outlined, size: 48),
                          SizedBox(height: 16),
                          Text(_search.isEmpty ? '还没有下载记录' : '没有匹配的结果'),
                          SizedBox(height: 8),
                          Text('解析链接后，点选清晰度开始下载'),
                        ],
                      ),
                    );
                  }
                  final record = visible[index - 1];
                  return DownloadTile(
                    key: ValueKey(record.taskId),
                    privacyMode: _private,
                    record: record,
                    loadThumbnail: () => repository.thumbnail(record.taskId),
                    selected: _selected.contains(record.taskId),
                    selectionMode: selected.isNotEmpty,
                    onSelect: _busy ? null : () => _select(record.taskId),
                    onActions: _busy ? null : () => _actions(context, record),
                    onOpen: () => _preview(context, record),
                    onCancel: () => runAction(
                      context,
                      () => repository.cancel(record.taskId),
                    ),
                    onRetry: () => runAction(context, () async {
                      await repository.retry(record.taskId);
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
}

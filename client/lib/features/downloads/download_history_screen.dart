import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/handed_layout.dart';
import '../../app/app_shell.dart';
import '../../app/library_search.dart';
import '../../core/models/app_failure.dart';
import '../../core/models/download.dart';
import '../../core/models/download_history.dart';
import '../../core/parsing/post_link.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/repositories/settings_repository.dart';

enum _HistoryAction { parse, copy, remove }

class DownloadHistoryScreen extends StatefulWidget {
  const DownloadHistoryScreen({
    super.key,
    required this.repository,
    required this.settings,
    required this.onParse,
  });
  final DownloadRepository repository;
  final SettingsRepository settings;
  final ValueChanged<String> onParse;
  @override
  State<DownloadHistoryScreen> createState() => _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends State<DownloadHistoryScreen> {
  late final _search = LibrarySearch(widget.settings);
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DownloadPhase? _filter;
  bool _busy = false;
  bool get _private => widget.settings.value.privacyMode;
  String _label(DownloadPhase phase) => switch (phase) {
    DownloadPhase.completed => '成功',
    DownloadPhase.failed => '失败',
    DownloadPhase.cancelled => '取消',
    _ => '进行中',
  };
  Uri? _post(DownloadHistoryEntry entry) => entry.postUrl == null
      ? null
      : PostLink.tryParse(entry.postUrl.toString())?.canonicalUrl;
  void _checkPrivacy() {
    if (_private) {
      throw const AppFailure(FailureKind.cancelled, '隐私模式已启用，无法查看下载历史');
    }
  }

  Future<void> _action(DownloadHistoryEntry entry, _HistoryAction action) =>
      runAction(context, () async {
        if (action == _HistoryAction.remove) {
          await widget.repository.removeHistory(entry.taskId);
          return;
        }
        _checkPrivacy();
        final post = _post(entry);
        if (post == null) {
          throw const AppFailure(FailureKind.invalidLink, '没有原帖子链接，无法重新解析');
        }
        if (action == _HistoryAction.copy) {
          await Clipboard.setData(ClipboardData(text: post.toString()));
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已复制链接')));
          }
        } else {
          widget.onParse(post.toString());
        }
      });
  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        actionsAlignment: HandedLayout.dialogAlignment(context),
        title: const Text('清空下载历史？'),
        content: const Text('只删除历史记录，不删除视频或取消正在下载的任务。'),
        actions: HandedLayout.actions(context, [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空'),
          ),
        ]),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await runAction(context, widget.repository.clearHistory);
    if (mounted) setState(() => _busy = false);
  }

  Widget _entry(BuildContext context, DownloadHistoryEntry entry) {
    final date = entry.createdAt.toLocal();
    final local = MaterialLocalizations.of(context);
    final post = _post(entry);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('history_${entry.taskId}'),
        onTap: _busy || (!_private && post == null)
            ? null
            : () => _action(entry, _HistoryAction.parse),
        child: Padding(
          padding: HandedLayout.isLeft(context)
              ? const EdgeInsets.fromLTRB(4, 12, 16, 12)
              : const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            textDirection: HandedLayout.rowDirection(context),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _private ? '已隐藏的下载历史' : entry.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${local.formatMediumDate(date)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)} · ${_label(entry.phase)}',
                    ),
                    if (!_private) ...[
                      const SizedBox(height: 4),
                      Text(
                        post?.toString() ?? '没有原帖子链接，无法重新解析',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_HistoryAction>(
                key: Key('history_actions_${entry.taskId}'),
                tooltip: '历史操作',
                enabled: !_busy,
                onSelected: (action) => _action(entry, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _HistoryAction.parse,
                    enabled: post != null,
                    child: const Text('重新解析'),
                  ),
                  PopupMenuItem(
                    value: _HistoryAction.copy,
                    enabled: post != null,
                    child: const Text('复制链接'),
                  ),
                  const PopupMenuItem(
                    value: _HistoryAction.remove,
                    child: Text('删除历史'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.repository, widget.settings, _search]),
    builder: (context, _) {
      final entries = widget.repository.history
          .where(
            (e) =>
                (_filter == null || e.phase == _filter) &&
                _search.matches([e.displayName, e.postUrl]),
          )
          .toList();
      return Scaffold(
        appBar: HandedAppBar(
          title: const Text('下载历史'),
          actions: [
            IconButton(
              tooltip: '清空历史',
              onPressed: _busy || widget.repository.history.isEmpty
                  ? null
                  : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (!_private)
                LibrarySearchField(search: _search, name: 'history'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in [
                      null,
                      DownloadPhase.completed,
                      DownloadPhase.failed,
                      DownloadPhase.cancelled,
                    ])
                      FilterChip(
                        label: Text(filter == null ? '全部' : _label(filter)),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(_search.isEmpty ? '没有符合条件的历史' : '没有匹配的结果'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: entries.length,
                        itemBuilder: (context, index) =>
                            _entry(context, entries[index]),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

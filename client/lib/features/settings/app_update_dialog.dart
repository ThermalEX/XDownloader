import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/models/app_update.dart';
import '../../data/repositories/update_repository.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  UpdateRepository repository, {
  bool check = false,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => AppUpdateDialog(repository: repository, check: check),
  );
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.repository,
    this.check = false,
  });
  final UpdateRepository repository;
  final bool check;
  @override
  State<AppUpdateDialog> createState() => _DialogState();
}

class _DialogState extends State<AppUpdateDialog> with WidgetsBindingObserver {
  UpdateRepository get repo => widget.repository;
  late bool _starting = widget.check;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo.setForegroundVisible(true);
    if (widget.check) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_check());
      });
    }
  }

  Future<void> _check() async {
    try {
      await repo.check();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      repo.setForegroundVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    repo.setForegroundVisible(false);
    super.dispose();
  }

  String _resultMessage() {
    if (repo.error != null) return repo.error!.message;
    final result = repo.result;
    if (result == null) return '选择渠道后检查新版本';
    if (!result.scopeComplete) return '部分发布未能验证，请稍后重试或查看发布页';
    if (result.validReleases == 0) return '暂未找到可用的更新发布';
    return '当前渠道没有更高版本';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final busy = _starting || repo.checking;
      final candidate = busy ? null : repo.result?.candidate;
      return AlertDialog(
        scrollable: true,
        title: Text(
          candidate == null ? '应用更新' : '发现新版本 ${candidate.versionName}',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                const Text('正在检查更新…'),
              ] else if (candidate != null) ...[
                Text(candidate.notes.isEmpty ? '此版本未提供更新说明' : candidate.notes),
                const SizedBox(height: 12),
                Text('安装包 ${_size(candidate.assets.first.bytes)}'),
                if (repo.result?.scopeComplete == false) ...[
                  const SizedBox(height: 12),
                  Text(_resultMessage()),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('不再提醒'),
                  value: !repo.preferences.showUpdatePrompt,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) => runAction(
                    context,
                    () => repo.setShowUpdatePrompt(!(value ?? false)),
                  ),
                ),
              ] else
                Text(_resultMessage()),
              if (repo.transfer.phase != UpdatePhase.idle) ...[
                const SizedBox(height: 16),
                _UpdateTransferView(repository: repo),
              ],
              if (!busy && repo.error != null && candidate != null)
                Text(
                  repo.error!.message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!busy)
                TextButton.icon(
                  onPressed: () => runAction(
                    context,
                    () => repo.openPage(candidate?.releasePage),
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('前往发布页下载'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (candidate != null && !repo.transfer.active)
            FilledButton.icon(
              onPressed: repo.operating
                  ? null
                  : () => runAction(context, repo.download),
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载更新'),
            ),
        ],
      );
    },
  );
}

String _size(int value) => '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';

class _UpdateTransferView extends StatelessWidget {
  const _UpdateTransferView({required this.repository});
  final UpdateRepository repository;
  @override
  Widget build(BuildContext context) {
    final repo = repository;
    final state = repo.transfer;
    final ready =
        state.phase == UpdatePhase.ready ||
        state.phase == UpdatePhase.permissionRequired;
    final total = state.totalBytes;
    final fraction = total == null || total <= 0
        ? null
        : (state.bytes / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ready && state.versionName != null) ...[
          Text(
            '待安装版本：${state.versionName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
        ],
        Text(switch (state.phase) {
          UpdatePhase.queued => '等待系统下载',
          UpdatePhase.running => '正在下载安装包',
          UpdatePhase.verifying => '正在校验安装包',
          UpdatePhase.ready => '安装包已验证，可以继续安装',
          UpdatePhase.permissionRequired => '请允许安装本应用提供的更新，然后继续安装',
          UpdatePhase.failed => state.error ?? '下载失败，请检查更新后重试',
          UpdatePhase.cancelled => '已取消更新下载',
          _ => '',
        }),
        if (state.active && !ready) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 8),
          Text(
            total == null
                ? '已下载 ${_size(state.bytes)}'
                : '${_size(state.bytes)} / ${_size(total)}',
          ),
        ],
        if (ready) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: repo.operating
                ? null
                : () => runAction(context, repo.install),
            icon: const Icon(Icons.install_mobile_outlined),
            label: const Text('继续安装'),
          ),
        ],
        if (state.active)
          TextButton(
            onPressed: repo.operating
                ? null
                : () => runAction(context, repo.cancelDownload),
            child: const Text('取消更新下载'),
          ),
      ],
    );
  }
}

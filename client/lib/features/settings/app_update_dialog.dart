import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/models/app_update.dart';
import '../../data/repositories/update_repository.dart';
import 'release_notes.dart';

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
    repo.addListener(_acknowledgeReady);
    repo.setForegroundVisible(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      owner: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _acknowledgeReady());
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

  void _acknowledgeReady() {
    if (mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed)) {
      repo.acknowledgeInstallPrompt();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    repo.setForegroundVisible(state == AppLifecycleState.resumed, owner: this);
    if (state == AppLifecycleState.resumed) _acknowledgeReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    repo.removeListener(_acknowledgeReady);
    repo.setForegroundVisible(false, owner: this);
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
      final downloading = const [
        UpdatePhase.queued,
        UpdatePhase.running,
        UpdatePhase.verifying,
      ].contains(repo.transfer.phase);
      final dismiss = TextButton(
        key: const Key('update_dialog_dismiss'),
        onPressed: () => Navigator.pop(context),
        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
        child: Text(downloading ? '后台继续' : '关闭', textAlign: TextAlign.center),
      );
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        titlePadding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        constraints: const BoxConstraints(maxWidth: 560),
        scrollable: true,
        title: Text(candidate?.displayTitle ?? '应用更新'),
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
                ReleaseNotes(
                  data: candidate.displayNotes.trim().isEmpty
                      ? '此版本未提供更新说明'
                      : candidate.displayNotes,
                  onOpenLink: (uri) => repo.openPage(uri),
                ),
                const SizedBox(height: 12),
                Text('安装包 ${_size(candidate.assets.first.bytes)}'),
                if (repo.result?.scopeComplete == false) ...[
                  const SizedBox(height: 12),
                  Text(_resultMessage()),
                ],
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
                Builder(
                  builder: (context) {
                    final compact =
                        MediaQuery.sizeOf(context).width -
                            MediaQuery.paddingOf(context).horizontal -
                            72 <
                        260;
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final label = compact || scale > 1.3 ? '发布页' : '前往发布页';
                    final browser = TextButton.icon(
                      key: const Key('update_dialog_release_page'),
                      onPressed: () => runAction(
                        context,
                        () => repo.openPage(candidate?.releasePage),
                      ),
                      icon: const Icon(Icons.open_in_new),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      label: Text(label),
                    );
                    if (candidate == null) {
                      return Align(
                        alignment: Alignment.centerRight,
                        child: browser,
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            dense: true,
                            title: Text(
                              '不再提醒',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            value: !repo.preferences.showUpdatePrompt,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (value) => runAction(
                              context,
                              () => repo.setShowUpdatePrompt(!(value ?? false)),
                            ),
                          ),
                        ),
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Tooltip(message: '前往发布页下载', child: browser),
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          if (repo.transfer.active)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('update_dialog_cancel_download'),
                    onPressed: repo.operating
                        ? null
                        : () => runAction(context, repo.cancelDownload),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('取消下载', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: dismiss),
              ],
            )
          else
            dismiss,
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

Future<void> showUpdateInstallDialog(
  BuildContext context,
  UpdateRepository repository,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('更新已下载'),
    scrollable: true,
    content: ListenableBuilder(
      listenable: repository,
      builder: (context, _) => _UpdateTransferView(repository: repository),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('稍后'),
      ),
    ],
  ),
);

class _UpdateTransferView extends StatelessWidget {
  const _UpdateTransferView({required this.repository});
  final UpdateRepository repository;
  @override
  Widget build(BuildContext context) {
    final repo = repository;
    final state = repo.transfer;
    final ready = state.ready;
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
      ],
    );
  }
}

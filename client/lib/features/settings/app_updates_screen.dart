import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/models/app_update.dart';
import '../../data/repositories/update_repository.dart';
import 'settings_group.dart';

class AppUpdatesScreen extends StatefulWidget {
  const AppUpdatesScreen({super.key, required this.repository});
  final UpdateRepository repository;
  @override
  State<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends State<AppUpdatesScreen>
    with WidgetsBindingObserver {
  UpdateRepository get repo => widget.repository;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo.setForegroundVisible(true);
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

  Future<void> _select(UpdateChannel channel) async {
    if (channel == repo.preferences.channel || repo.operating) return;
    if (repo.transfer.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('取消下载并切换渠道？'),
          content: const Text('会移除当前更新安装包，切换后重新检查。视频下载不受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('继续当前下载'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('取消并切换'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await runAction(context, () async {
        await repo.cancelDownload();
        await repo.setChannel(channel);
      });
    } else {
      await runAction(context, () => repo.setChannel(channel));
    }
  }

  String _status() {
    if (repo.checking) return '正在检查更新…';
    final result = repo.result;
    if (result == null) return '选择渠道后检查新版本';
    if (result.candidate != null) {
      return '发现新版本 ${result.candidate!.versionName}';
    }
    if (!result.scopeComplete) return '部分发布未能验证，请稍后重试或查看发布页';
    if (result.validReleases == 0) return '暂未找到可用的更新发布';
    return '当前渠道没有更高版本';
  }

  Widget _transfer() {
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

  String _size(int value) => '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
      final candidate = repo.result?.candidate;
      return Scaffold(
        appBar: AppBar(title: const Text('应用更新')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              SettingsGroup(
                title: '版本',
                children: [
                  ListTile(
                    leading: const SettingsIcon(Icons.system_update_outlined),
                    title: const Text('当前版本'),
                    subtitle: Text(repo.installed?.versionName ?? '暂时无法读取版本'),
                  ),
                ],
              ),
              SettingsGroup(
                title: '更新渠道',
                children: [
                  RadioGroup<UpdateChannel>(
                    groupValue: repo.preferences.channel,
                    onChanged: (value) {
                      if (value != null) unawaited(_select(value));
                    },
                    child: Column(
                      children: [
                        RadioListTile<UpdateChannel>(
                          key: const Key('update_channel_stable'),
                          value: UpdateChannel.stable,
                          title: const Text('稳定版'),
                          subtitle: const Text('仅接收正式发布，推荐日常使用'),
                          enabled: !repo.operating,
                        ),
                        RadioListTile<UpdateChannel>(
                          key: const Key('update_channel_beta'),
                          value: UpdateChannel.beta,
                          title: const Text('Beta 版'),
                          subtitle: const Text('包含测试版与正式版，可提前体验新功能'),
                          enabled: !repo.operating,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('切回稳定版不会自动降级；请等待更高版本的稳定版。'),
              ),
              SettingsGroup(
                title: '检查与下载',
                children: [
                  SwitchListTile(
                    title: const Text('启动时检查更新'),
                    subtitle: const Text('每天最多自动检查一次，不自动下载'),
                    value: repo.preferences.autoCheck,
                    onChanged: (value) =>
                        runAction(context, () => repo.setAutoCheck(value)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _status(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (repo.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            repo.error!.message,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: repo.checking || repo.operating
                              ? null
                              : () => repo.check(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('检查更新'),
                        ),
                        if (candidate != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            candidate.notes.isEmpty
                                ? '此版本未提供更新说明'
                                : candidate.notes,
                          ),
                          const SizedBox(height: 8),
                          Text('安装包 ${_size(candidate.assets.first.bytes)}'),
                          if (!repo.transfer.active) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: repo.operating
                                  ? null
                                  : () => runAction(context, repo.download),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('下载更新'),
                            ),
                          ],
                        ],
                        if (repo.transfer.phase != UpdatePhase.idle) ...[
                          const SizedBox(height: 16),
                          _transfer(),
                        ],
                        const SizedBox(height: 8),
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
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

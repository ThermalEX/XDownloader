import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/models/app_update.dart';
import '../../data/repositories/update_repository.dart';
import 'settings_group.dart';
import 'app_update_dialog.dart';

class AppUpdatesScreen extends StatefulWidget {
  const AppUpdatesScreen({super.key, required this.repository});
  final UpdateRepository repository;
  @override
  State<AppUpdatesScreen> createState() => _AppUpdatesScreenState();
}

class _AppUpdatesScreenState extends State<AppUpdatesScreen> {
  UpdateRepository get repo => widget.repository;
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repo,
    builder: (context, _) {
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
                    subtitle: const Text('每次启动检查，不自动下载'),
                    value: repo.preferences.autoCheck,
                    onChanged: (value) =>
                        runAction(context, () => repo.setAutoCheck(value)),
                  ),
                  SwitchListTile(
                    title: const Text('启动时提醒新版'),
                    subtitle: const Text('关闭后不自动弹窗，手动检查仍显示结果'),
                    value: repo.preferences.showUpdatePrompt,
                    onChanged: (value) => runAction(
                      context,
                      () => repo.setShowUpdatePrompt(value),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('update_check'),
                          onPressed: repo.operating
                              ? null
                              : () => showAppUpdateDialog(
                                  context,
                                  repo,
                                  check: true,
                                ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('检查更新'),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          key: const Key('update_release_page'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          onPressed: () =>
                              runAction(context, () => repo.openPage()),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('前往发布页下载'),
                        ),
                      ],
                    ),
                  ),
                  if (repo.transfer.phase != UpdatePhase.idle)
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('查看更新下载'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAppUpdateDialog(context, repo),
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

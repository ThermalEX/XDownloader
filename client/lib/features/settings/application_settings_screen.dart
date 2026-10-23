import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/settings_repository.dart';

import 'settings_group.dart';
import 'privacy_password_dialog.dart';

class ApplicationSettingsScreen extends StatelessWidget {
  const ApplicationSettingsScreen({super.key, required this.repository});
  final SettingsRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('应用设置')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: repository,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsPanel(
              title: '隐私保护',
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('privacy_mode_switch'),
                    title: const Text('隐私模式'),
                    subtitle: const Text('保留首页解析，隐藏收藏与历史、模糊下载封面与名称，并禁止打开视频'),
                    value: repository.value.privacyMode,
                    onChanged: (value) =>
                        !value &&
                            repository.value.privacyPasswordHash.isNotEmpty
                        ? showPrivacyPasswordDialog(
                            context,
                            repository,
                            unlockOnly: true,
                          )
                        : runAction(
                            context,
                            () => repository.setPrivacyMode(value),
                          ),
                  ),
                  ListTile(
                    key: const Key('privacy_password_setting'),
                    title: const Text('隐私 PIN'),
                    subtitle: Text(
                      repository.value.privacyPasswordHash.isEmpty
                          ? '未设置（无密码）'
                          : '已设置，关闭隐私模式时验证',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showPrivacyPasswordDialog(context, repository),
                  ),
                ],
              ),
            ),
            SettingsPanel(
              title: '剪贴板',
              child: SwitchListTile(
                title: const Text('自动读取剪贴板'),
                subtitle: const Text('回到解析页时识别新链接，保留手动输入'),
                value: repository.value.autoClipboard,
                onChanged: (value) => runAction(
                  context,
                  () =>
                      repository.edit((s) => s.copyWith(autoClipboard: value)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

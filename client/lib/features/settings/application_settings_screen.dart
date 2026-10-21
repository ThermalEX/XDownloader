import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/settings_repository.dart';

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
            SwitchListTile(
              title: const Text('隐私模式'),
              subtitle: const Text('模糊下载封面与名称、隐藏收藏，并禁止打开视频'),
              value: repository.value.privacyMode,
              onChanged: (value) => runAction(
                context,
                () => repository.edit((s) => s.copyWith(privacyMode: value)),
              ),
            ),
            SwitchListTile(
              title: const Text('自动读取剪贴板'),
              subtitle: const Text('回到解析页时识别新链接，保留手动输入'),
              value: repository.value.autoClipboard,
              onChanged: (value) => runAction(
                context,
                () => repository.edit((s) => s.copyWith(autoClipboard: value)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

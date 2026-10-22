import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import 'appearance_screen.dart';
import 'rule_settings_screen.dart';
import 'application_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'about_screen.dart';
import 'settings_group.dart';
import 'app_updates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.dependencies, this.onOpenTab});
  final AppDependencies dependencies;
  final ValueChanged<int>? onOpenTab;

  @override
  Widget build(BuildContext context) {
    Widget entry(String title, String subtitle, IconData icon, Widget screen) =>
        ListTile(
          leading: SettingsIcon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => screen),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        SettingsGroup(
          grouped: true,
          title: '资源',
          children: [
            entry(
              '规则设置',
              '下载源、自动换源与重命名规则',
              Icons.extension_outlined,
              RuleSettingsScreen(dependencies: dependencies),
            ),
            entry(
              '下载与存储',
              '下载文件夹与记录管理',
              Icons.folder_outlined,
              StorageSettingsScreen(repository: dependencies.downloads),
            ),
          ],
        ),
        SettingsGroup(
          grouped: true,
          title: '应用',
          children: [
            entry(
              '外观设置',
              '主题模式、主题色与动态取色',
              Icons.palette_outlined,
              AppearanceScreen(repository: dependencies.settings),
            ),
            entry(
              '应用设置',
              '剪贴板与隐私模式',
              Icons.settings_outlined,
              ApplicationSettingsScreen(repository: dependencies.settings),
            ),
          ],
        ),
        SettingsGroup(
          grouped: true,
          title: '其他',
          children: [
            KeyedSubtree(
              key: const Key('settings_updates'),
              child: entry(
                '应用更新',
                '稳定版与 Beta 版、检查更新',
                Icons.system_update_outlined,
                AppUpdatesScreen(repository: dependencies.updates),
              ),
            ),
            entry(
              '关于',
              '版本与开源信息',
              Icons.info_outline,
              AboutScreen(dependencies: dependencies, onOpenTab: onOpenTab),
            ),
          ],
        ),
      ],
    );
  }
}

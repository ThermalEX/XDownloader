import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import '../../app/app_shell.dart';
import '../../data/updates/github_release_client.dart';
import 'settings_group.dart';
import 'usage_guide_screen.dart';
import 'changelog_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.dependencies, this.onOpenTab});
  final AppDependencies dependencies;
  final ValueChanged<int>? onOpenTab;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsPanel(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Image.asset(
                    'assets/branding/app_icon.png',
                    width: 120,
                    height: 120,
                    cacheWidth: 384,
                    semanticLabel: 'XDownloader 图标',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'XDownloader',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: dependencies.updates,
                    builder: (context, _) => Text(
                      dependencies.updates.installed?.versionName ?? '版本暂不可用',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsPanel(
            child: ListTile(
              key: const Key('usage_guide_entry'),
              leading: const SettingsIcon(Icons.menu_book_outlined),
              title: const Text('使用说明'),
              subtitle: const Text('下载、收藏、播放器与更新'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UsageGuideScreen(
                    dependencies: dependencies,
                    onOpenTab: onOpenTab,
                  ),
                ),
              ),
            ),
          ),
          SettingsPanel(
            child: ListTile(
              key: const Key('changelog_entry'),
              minTileHeight: 72,
              leading: const SettingsIcon(Icons.history_outlined),
              title: const Text('更新日志'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ChangelogScreen(updates: dependencies.updates),
                ),
              ),
            ),
          ),
          SettingsPanel(
            child: ListTile(
              leading: const SettingsIcon(Icons.person_outline),
              title: const Text('作者'),
              subtitle: const Text('ThermalEX'),
            ),
          ),
          const SettingsPanel(
            child: ListTile(
              leading: SettingsIcon(Icons.layers_outlined),
              title: Text('技术栈'),
              subtitle: Text('Flutter · Dart · Material 3\nAndroid · Kotlin'),
            ),
          ),
          SettingsPanel(
            child: ListTile(
              leading: const SettingsIcon(Icons.code),
              title: const Text('GitHub 源码仓库'),
              subtitle: const Text('ThermalEX/XDownloader'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => runAction(
                context,
                () => dependencies.updates.openPage(
                  GitHubReleaseClient.repositoryPage,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '从 X 帖子提取视频并保存到公共下载文件夹。请仅保存你有权使用的内容。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (dependencies.migration?.errors.isNotEmpty ?? false) ...[
            const SizedBox(height: 24),
            const Text('部分旧数据未能导入，原数据已保留；下次启动会重试。'),
            for (final error in dependencies.migration!.errors)
              Text(error.message),
          ],
        ],
      ),
    ),
  );
}

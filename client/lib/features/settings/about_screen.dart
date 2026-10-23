import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import '../../app/app_shell.dart';
import '../../data/updates/github_release_client.dart';
import 'settings_group.dart';
import 'usage_guide_screen.dart';
import 'changelog_screen.dart';
import 'avatar_easter_egg.dart';

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
                  AvatarEasterEgg(settings: dependencies.settings),
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
            child: _AboutInfoTile(
              tileKey: const Key('usage_guide_entry'),
              icon: Icons.menu_book_outlined,
              title: '使用说明',
              subtitle: '下载、收藏、播放器与更新',
              trailing: Icons.chevron_right,
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
            child: _AboutInfoTile(
              tileKey: const Key('changelog_entry'),
              icon: Icons.history_outlined,
              title: '更新日志',
              trailing: Icons.chevron_right,
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
            child: _AboutInfoTile(
              icon: Icons.person_outline,
              title: '作者',
              subtitle: 'ThermalEX',
            ),
          ),
          const SettingsPanel(
            child: _AboutInfoTile(
              icon: Icons.layers_outlined,
              title: '技术栈',
              subtitle: 'Flutter · Dart · Material 3 · Android · Kotlin',
              details: 'Flutter · Dart · Material 3\nAndroid · Kotlin',
            ),
          ),
          SettingsPanel(
            child: _AboutInfoTile(
              icon: Icons.code,
              title: 'GitHub 源码仓库',
              subtitle: 'ThermalEX/XDownloader',
              trailing: Icons.open_in_new,
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

class _AboutInfoTile extends StatelessWidget {
  const _AboutInfoTile({
    this.tileKey,
    required this.icon,
    required this.title,
    this.subtitle,
    this.details,
    this.trailing,
    this.onTap,
  });

  final Key? tileKey;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? details;
  final IconData? trailing;
  final VoidCallback? onTap;

  void _showDetails(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: colors.surface.withValues(
        alpha: colors.brightness == Brightness.dark ? 0.56 : 0.32,
      ),
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: subtitle == null ? null : Text(details ?? subtitle!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleMedium!;
    final subtitleStyle = textTheme.bodyMedium!;
    final height = settingsRowHeight(context);
    return SizedBox(
      height: height,
      child: Semantics(
        hint: onTap == null ? '轻触查看完整文字' : '长按查看完整文字',
        child: ListTile(
          key: tileKey,
          minTileHeight: height,
          minVerticalPadding: 8,
          titleTextStyle: titleStyle,
          subtitleTextStyle: subtitleStyle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          leading: SettingsIcon(icon),
          title: Text(
            title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
          trailing: trailing == null ? null : Icon(trailing),
          onTap: onTap ?? () => _showDetails(context),
          onLongPress: onTap == null ? null : () => _showDetails(context),
        ),
      ),
    );
  }
}

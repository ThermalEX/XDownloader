import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import '../../app/app_shell.dart';
import '../../data/updates/github_release_client.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.downloading, size: 56),
          const SizedBox(height: 16),
          Text('XDownloader', style: Theme.of(context).textTheme.headlineSmall),
          ListenableBuilder(
            listenable: dependencies.updates,
            builder: (context, _) => Text(
              '${dependencies.updates.installed?.versionName ?? '版本暂不可用'} · Flutter Material 3',
            ),
          ),
          TextButton.icon(
            onPressed: () => runAction(
              context,
              () => dependencies.updates.openPage(
                GitHubReleaseClient.repositoryPage,
              ),
            ),
            icon: const Icon(Icons.code),
            label: const Text('GitHub 源码仓库'),
          ),
          const SizedBox(height: 24),
          const Text('从 X 帖子中提取视频，保存到公共下载文件夹。后台下载由 Android 系统管理，离开应用后仍可继续。'),
          const SizedBox(height: 16),
          const Text('请仅保存你有权使用的内容。'),
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

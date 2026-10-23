import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/download_repository.dart';

import 'settings_group.dart';
import 'cover_cache_screen.dart';

class StorageSettingsScreen extends StatelessWidget {
  const StorageSettingsScreen({super.key, required this.repository});
  final DownloadRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('下载与存储')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (repository.coverCache case final cache?)
            SettingsPanel(
              child: ListenableBuilder(
                listenable: cache,
                builder: (context, _) => ListTile(
                  key: const Key('cover_cache_settings'),
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('封面缓存'),
                  subtitle: Text(
                    '${cacheSize(cache.usedBytes)} / ${cache.limitMb} MB',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CoverCacheScreen(cache: cache),
                    ),
                  ),
                ),
              ),
            ),
          SettingsPanel(
            title: '文件存储',
            child: ListTile(
              title: const Text('下载文件夹'),
              subtitle: const Text('Download/XDownloader'),
              leading: const Icon(Icons.folder_outlined),
              onTap: () => runAction(context, repository.openDirectory),
            ),
          ),
          SettingsPanel(
            title: '记录管理',
            child: ListTile(
              title: const Text('清空下载记录'),
              subtitle: const Text('保留活动任务、视频文件和独立下载历史'),
              leading: const Icon(Icons.history),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('清空下载记录？'),
                    content: const Text('只移除下载列表中已结束的条目，视频文件和独立下载历史均保留。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await runAction(context, repository.clearCompletedHistory);
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}

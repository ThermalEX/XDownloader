import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/cover_cache_repository.dart';
import 'settings_group.dart';

String cacheSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class CoverCacheScreen extends StatelessWidget {
  const CoverCacheScreen({super.key, required this.cache});
  final CoverCacheRepository cache;

  Future<void> _limit(BuildContext context) async {
    var input = '${cache.limitMb}';
    String? error;
    final value = await showDialog<int>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('缓存大小上限'),
          content: TextFormField(
            key: const Key('cover_cache_limit_input'),
            initialValue: input,
            onChanged: (value) => input = value,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '大小（MB）',
              helperText: '0–2048，0 表示不保留磁盘缓存',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(input);
                if (value == null || value < 0 || value > 2048) {
                  setState(() => error = '请输入 0–2048 之间的整数');
                  return;
                }
                Navigator.pop(dialog, value);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (value != null && context.mounted) {
      await runAction(context, () => cache.setLimitMb(value));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('封面缓存')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: cache,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SettingsPanel(
              child: Column(
                children: [
                  ListTile(
                    leading: const SettingsIcon(Icons.photo_library_outlined),
                    title: const Text('已用缓存'),
                    subtitle: Text(
                      '${cacheSize(cache.usedBytes)} · ${cache.entries.length} 张封面',
                    ),
                  ),
                  ListTile(
                    key: const Key('cover_cache_limit'),
                    leading: const SettingsIcon(Icons.data_usage),
                    title: const Text('缓存大小上限'),
                    subtitle: Text(
                      cache.limitMb == 0 ? '不保留磁盘缓存' : '${cache.limitMb} MB',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _limit(context),
                  ),
                  ListTile(
                    key: const Key('cover_cache_view'),
                    leading: const SettingsIcon(Icons.grid_view_outlined),
                    title: const Text('查看缓存'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => _CachedCovers(cache: cache),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SettingsPanel(
              child: ListTile(
                key: const Key('cover_cache_clear'),
                leading: const SettingsIcon(Icons.cleaning_services_outlined),
                title: const Text('清理封面缓存'),
                onTap: () => runAction(context, () async {
                  await cache.clear();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已清理封面缓存')));
                  }
                }),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CachedCovers extends StatelessWidget {
  const _CachedCovers({required this.cache});
  final CoverCacheRepository cache;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('查看缓存')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([cache, cache.settings]),
        builder: (context, _) {
          if (cache.settings.value.privacyMode) {
            return const Center(child: Text('隐私模式已启动，无法查看封面'));
          }
          final entries = cache.entries;
          if (entries.isEmpty) return const Center(child: Text('还没有封面缓存'));
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisExtent: 170,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) => Card.filled(
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        entries[index].file,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        cacheWidth: 320,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(cacheSize(entries[index].bytes)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

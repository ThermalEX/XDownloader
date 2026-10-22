import 'package:flutter/material.dart';

import '../../data/repositories/favorite_repository.dart';
import '../../data/repositories/settings_repository.dart';

class FavoriteFilterSheet extends StatefulWidget {
  const FavoriteFilterSheet({
    super.key,
    required this.favorites,
    required this.settings,
    this.category,
  });
  final FavoriteRepository favorites;
  final SettingsRepository settings;
  final String? category;
  @override
  State<FavoriteFilterSheet> createState() => _FilterState();
}

class _FilterState extends State<FavoriteFilterSheet> {
  late FavoriteSort _sort = widget.favorites.sort;
  late String? _category = widget.category;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.settings, widget.favorites]),
    builder: (context, _) {
      if (widget.settings.value.privacyMode) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('隐私模式已启动，无法查看收藏'),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        );
      }
      final groups = {
        ...widget.favorites.categories,
        if (_category?.isNotEmpty ?? false) _category!,
      }.toList()..sort();
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      );
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '排序与分类',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('排序'),
                      ),
                      RadioGroup<FavoriteSort>(
                        groupValue: _sort,
                        onChanged: (value) {
                          if (value != null) setState(() => _sort = value);
                        },
                        child: Column(
                          children: [
                            for (final option in const [
                              (FavoriteSort.defaultOrder, '默认顺序'),
                              (FavoriteSort.newest, '最新收藏'),
                              (FavoriteSort.oldest, '最早收藏'),
                              (FavoriteSort.title, '名称顺序'),
                            ])
                              RadioListTile<FavoriteSort>(
                                value: option.$1,
                                title: Text(option.$2),
                                shape: shape,
                              ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('分类'),
                      ),
                      RadioGroup<String>(
                        groupValue: _category == null
                            ? 'all'
                            : 'category:$_category',
                        onChanged: (value) {
                          if (value != null) {
                            setState(
                              () => _category = value == 'all'
                                  ? null
                                  : value.substring(9),
                            );
                          }
                        },
                        child: Column(
                          children: [
                            const RadioListTile<String>(
                              value: 'all',
                              title: Text('全部'),
                              shape: shape,
                            ),
                            const RadioListTile<String>(
                              value: 'category:',
                              title: Text('未分类'),
                              shape: shape,
                            ),
                            for (final group in groups)
                              RadioListTile<String>(
                                value: 'category:$group',
                                title: Text(group),
                                shape: shape,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        if (!widget.settings.value.privacyMode) {
                          Navigator.pop(context, (_sort, _category));
                        }
                      },
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

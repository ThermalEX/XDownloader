import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell.dart';
import '../../app/bootstrap.dart';
import '../../app/favorite_icon.dart';
import '../../core/models/app_failure.dart';
import '../../core/models/favorite_link.dart';
import '../../data/repositories/favorite_repository.dart';
import '../../core/parsing/post_link.dart';
import 'favorite_filter_sheet.dart';
import 'favorite_category_bar.dart';

void _ensureVisible(AppDependencies dependencies) {
  if (dependencies.settings.value.privacyMode) {
    throw const AppFailure(FailureKind.cancelled, '隐私模式已启动，无法查看收藏');
  }
}

Future<void> _add(
  BuildContext context,
  AppDependencies dependencies, {
  required bool clipboard,
}) => runAction(context, () async {
  _ensureVisible(dependencies);
  String? text;
  if (clipboard) {
    text = await dependencies.readClipboard();
    if (!context.mounted) return;
    if (text == null || text.trim().isEmpty) {
      throw const AppFailure(FailureKind.invalidLink, '剪贴板中没有帖子链接');
    }
  } else {
    text = await showDialog<String>(
      context: context,
      builder: (_) => const _FavoriteInputDialog(),
    );
  }
  if (text == null || !context.mounted) return;
  _ensureVisible(dependencies);
  final added = await dependencies.favorites.add(text);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(added ? '已收藏链接' : '该链接已在收藏列表中')));
  }
});

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.dependencies,
    required this.onOpen,
  });
  final AppDependencies dependencies;
  final ValueChanged<String> onOpen;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  AppDependencies get dependencies => widget.dependencies;
  Set<String> _categories = {};
  Future<void> _filter() => runAction(context, () async {
    _ensureVisible(dependencies);
    final choice = await showModalBottomSheet<(FavoriteSort, Set<String>)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => FavoriteFilterSheet(
        favorites: dependencies.favorites,
        settings: dependencies.settings,
        categories: _categories,
      ),
    );
    if (choice == null || !mounted) return;
    _ensureVisible(dependencies);
    await dependencies.favorites.setSort(choice.$1);
    if (mounted) {
      _ensureVisible(dependencies);
      setState(() => _categories = choice.$2);
    }
  });

  Future<void> _addCategory() => runAction(context, () async {
    _ensureVisible(dependencies);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryInputDialog(dependencies: dependencies),
    );
    if (name == null || !mounted) return;
    _ensureVisible(dependencies);
    final added = await dependencies.favorites.addCategory(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(added ? '已添加分类' : '该分类已存在')));
  });

  Future<void> _remove(String id) => runAction(context, () async {
    _ensureVisible(dependencies);
    final removed = await dependencies.favorites.removeForUndo(id);
    if (!mounted || removed == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已取消收藏'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '撤回',
          onPressed: () {
            if (mounted) {
              runAction(context, () async {
                _ensureVisible(dependencies);
                await dependencies.favorites.restore(removed);
              });
            }
          },
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      dependencies.settings,
      dependencies.favorites,
    ]),
    builder: (context, _) {
      if (dependencies.settings.value.privacyMode) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_off_outlined, size: 48),
                SizedBox(height: 16),
                Text('隐私模式已启动，无法查看收藏', textAlign: TextAlign.center),
                SizedBox(height: 8),
                Text('关闭隐私模式后恢复显示', textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }
      final selected = _categories;
      final active =
          dependencies.favorites.sort != FavoriteSort.defaultOrder ||
          selected.isNotEmpty;
      final colors = Theme.of(context).colorScheme;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: FavoriteCategoryBar(
                    categories: dependencies.favorites.categories,
                    selected: selected,
                    onSelected: (category) {
                      if (!dependencies.settings.value.privacyMode) {
                        setState(
                          () =>
                              _categories = category == null ? {} : {category},
                        );
                      }
                    },
                  ),
                ),
                IconButton(
                  key: const Key('favorite_add_category'),
                  tooltip: '新增分类',
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  key: const Key('favorite_filter'),
                  tooltip: active ? '排序与分类（已筛选）' : '排序与分类',
                  isSelected: active,
                  style: IconButton.styleFrom(
                    backgroundColor: active
                        ? colors.primaryContainer
                        : colors.secondaryContainer,
                    foregroundColor: active
                        ? colors.primary
                        : colors.onSecondaryContainer,
                  ),
                  onPressed: _filter,
                  icon: const Icon(Icons.filter_list_alt),
                  selectedIcon: const Icon(Icons.filter_list_alt),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: dependencies.favorites,
              builder: (context, _) {
                final items = dependencies.favorites.items
                    .where(
                      (f) => selected.isEmpty || selected.contains(f.category),
                    )
                    .toList();
                if (items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 48),
                      const Icon(Icons.favorite_border, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        selected.isEmpty ? '还没有收藏' : '所选分类还没有收藏',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '收藏帖子链接，下次可直接点按解析',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card.filled(
                      child: ListTile(
                        key: Key('favorite_${item.postId}'),
                        leading: IconButton(
                          key: Key('favorite_remove_${item.postId}'),
                          tooltip: '取消收藏',
                          onPressed: () => _remove(item.postId),
                          icon: Icon(
                            Icons.favorite,
                            color: savedHeartColor(context),
                          ),
                        ),
                        title: Text(
                          item.title.isEmpty
                              ? 'X 帖子 ${item.postId}'
                              : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.category.isEmpty ? '' : '${item.category} · '}${item.url}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => runAction(context, () async {
                          _ensureVisible(dependencies);
                          widget.onOpen(item.url.toString());
                        }),
                        trailing: PopupMenuButton<String>(
                          key: Key('favorite_actions_${item.postId}'),
                          tooltip: '收藏操作',
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          onSelected: (action) => runAction(context, () async {
                            _ensureVisible(dependencies);
                            if (action == 'rename' || action == 'category') {
                              await _editFavorite(
                                context,
                                dependencies,
                                item,
                                category: action == 'category',
                              );
                            } else if (action == 'copy') {
                              await Clipboard.setData(
                                ClipboardData(text: item.url.toString()),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制链接')),
                                );
                              }
                            } else {
                              await _remove(item.postId);
                            }
                          }),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('重命名')),
                            PopupMenuItem(value: 'category', child: Text('分类')),
                            PopupMenuItem(value: 'copy', child: Text('复制链接')),
                            PopupMenuItem(value: 'remove', child: Text('取消收藏')),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

Future<void> _editFavorite(
  BuildContext context,
  AppDependencies dependencies,
  FavoriteLink item, {
  required bool category,
}) async {
  _ensureVisible(dependencies);
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _FavoriteEditDialog(
      dependencies: dependencies,
      item: item,
      categoryFirst: category,
    ),
  );
  if (result == null || !context.mounted) return;
  _ensureVisible(dependencies);
  await dependencies.favorites.update(
    item.postId,
    title: result.$1,
    category: result.$2,
  );
}

class _FavoriteEditDialog extends StatefulWidget {
  const _FavoriteEditDialog({
    required this.dependencies,
    required this.item,
    required this.categoryFirst,
  });
  final AppDependencies dependencies;
  final FavoriteLink item;
  final bool categoryFirst;
  @override
  State<_FavoriteEditDialog> createState() => _FavoriteEditState();
}

class _FavoriteEditState extends State<_FavoriteEditDialog> {
  late final _title = TextEditingController(
    text: widget.item.title.isEmpty
        ? 'X 帖子 ${widget.item.postId}'
        : widget.item.title,
  );
  late final _category = TextEditingController(text: widget.item.category);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.settings,
    builder: (context, _) {
      final hidden = widget.dependencies.settings.value.privacyMode;
      return AlertDialog(
        title: Text(hidden ? '隐私模式已启动，无法查看收藏' : '编辑收藏'),
        scrollable: true,
        content: hidden
            ? null
            : Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('favorite_title'),
                      controller: _title,
                      maxLength: 300,
                      autofocus: !widget.categoryFirst,
                      decoration: const InputDecoration(labelText: '名称'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入名称'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('favorite_category'),
                      controller: _category,
                      maxLength: 40,
                      autofocus: widget.categoryFirst,
                      decoration: const InputDecoration(
                        labelText: '分类',
                        helperText: '留空表示未分类，可输入新分类',
                      ),
                    ),
                    if (widget.dependencies.favorites.categories.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final group
                              in widget.dependencies.favorites.categories)
                            ActionChip(
                              label: Text(group),
                              onPressed: () => _category.text = group,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (!hidden)
            FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, (_title.text, _category.text));
                }
              },
              child: const Text('保存'),
            ),
        ],
      );
    },
  );
}

class _CategoryInputDialog extends StatefulWidget {
  const _CategoryInputDialog({required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<_CategoryInputDialog> createState() => _CategoryInputState();
}

class _CategoryInputState extends State<_CategoryInputDialog> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.settings,
    builder: (context, _) {
      final hidden = widget.dependencies.settings.value.privacyMode;
      return AlertDialog(
        title: Text(hidden ? '隐私模式已启动，无法查看收藏' : '新增分类'),
        scrollable: true,
        content: hidden
            ? null
            : Form(
                key: _form,
                child: TextFormField(
                  key: const Key('favorite_category_name'),
                  controller: _name,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '分类名称'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入分类名称' : null,
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (!hidden)
            FilledButton(
              onPressed: () {
                if (!widget.dependencies.settings.value.privacyMode &&
                    _form.currentState!.validate()) {
                  Navigator.pop(context, _name.text.trim());
                }
              },
              child: const Text('添加'),
            ),
        ],
      );
    },
  );
}

class _FavoriteInputDialog extends StatefulWidget {
  const _FavoriteInputDialog();
  @override
  State<_FavoriteInputDialog> createState() => _FavoriteInputState();
}

class _FavoriteInputState extends State<_FavoriteInputDialog> {
  final _text = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加收藏'),
    scrollable: true,
    content: TextField(
      key: const Key('favorite_input'),
      controller: _text,
      autofocus: true,
      minLines: 1,
      maxLines: 4,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(labelText: 'X 帖子链接或分享文案', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (PostLink.tryParse(_text.text) == null) {
            setState(() => _error = '请输入有效的 X 帖子链接');
          } else {
            Navigator.pop(context, _text.text);
          }
        },
        child: const Text('收藏'),
      ),
    ],
  );
}

class FavoritesActions extends StatelessWidget {
  const FavoritesActions({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dependencies.settings,
    builder: (context, _) => dependencies.settings.value.privacyMode
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () =>
                          _add(context, dependencies, clipboard: false),
                      icon: const Icon(Icons.add),
                      label: const Text('添加链接', textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () =>
                          _add(context, dependencies, clipboard: true),
                      icon: const Icon(Icons.content_paste),
                      label: const Text('从剪贴板添加', textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

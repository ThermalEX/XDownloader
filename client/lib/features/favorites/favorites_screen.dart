import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell.dart';
import '../../app/bootstrap.dart';
import '../../core/models/app_failure.dart';
import '../../core/parsing/post_link.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    super.key,
    required this.dependencies,
    required this.onOpen,
  });
  final AppDependencies dependencies;
  final ValueChanged<String> onOpen;

  void _ensureVisible() {
    if (dependencies.settings.value.privacyMode) {
      throw const AppFailure(FailureKind.cancelled, '隐私模式已启动，无法查看收藏');
    }
  }

  Future<void> _add(BuildContext context, {required bool clipboard}) =>
      runAction(context, () async {
        _ensureVisible();
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
        _ensureVisible();
        final added = await dependencies.favorites.add(text);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(added ? '已收藏链接' : '该链接已在收藏列表中')),
          );
        }
      });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dependencies.settings,
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
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _add(context, clipboard: false),
                  icon: const Icon(Icons.add),
                  label: const Text('添加链接'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _add(context, clipboard: true),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('从剪贴板添加'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: dependencies.favorites,
              builder: (context, _) {
                final items = dependencies.favorites.items;
                if (items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(32),
                    children: const [
                      SizedBox(height: 48),
                      Icon(Icons.bookmark_outline, size: 48),
                      SizedBox(height: 16),
                      Text('还没有收藏', textAlign: TextAlign.center),
                      SizedBox(height: 8),
                      Text('收藏帖子链接，下次可直接点按解析', textAlign: TextAlign.center),
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
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(
                          item.title.isEmpty
                              ? 'X 帖子 ${item.postId}'
                              : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.url.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => runAction(context, () async {
                          _ensureVisible();
                          onOpen(item.url.toString());
                        }),
                        trailing: PopupMenuButton<bool>(
                          key: Key('favorite_actions_${item.postId}'),
                          tooltip: '收藏操作',
                          onSelected: (copy) => runAction(context, () async {
                            _ensureVisible();
                            if (copy) {
                              await Clipboard.setData(
                                ClipboardData(text: item.url.toString()),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制链接')),
                                );
                              }
                            } else {
                              await dependencies.favorites.remove(item.postId);
                            }
                          }),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: true, child: Text('复制链接')),
                            PopupMenuItem(value: false, child: Text('取消收藏')),
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

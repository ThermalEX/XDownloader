import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/parsing/post_link.dart';
import '../settings/sources_screen.dart';
import 'home_controller.dart';
import 'media_result_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final HomeController controller;
  @override
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final home = widget.controller;
      if (_text.text != home.input) {
        _text.value = TextEditingValue(
          text: home.input,
          selection: TextSelection.collapsed(offset: home.input.length),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('保存喜欢的视频', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('粘贴 X 帖子链接或分享文案，选择清晰度即可保存。'),
          const SizedBox(height: 24),
          TextField(
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            controller: _text,
            onChanged: home.setInput,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: home.parse,
            decoration: InputDecoration(
              labelText: '视频链接',
              hintText: 'https://x.com/…/status/…',
              suffixIcon: IconButton(
                tooltip: '清空',
                onPressed: home.clear,
                icon: const Icon(Icons.clear),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Semantics(
                label: '从剪贴板粘贴',
                excludeSemantics: true,
                button: true,
                child: OutlinedButton.icon(
                  onPressed: () => runAction(context, home.paste),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('粘贴'),
                ),
              ),
              Semantics(
                label: '解析链接',
                excludeSemantics: true,
                button: true,
                child: FilledButton.icon(
                  onPressed: home.busy
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          home.parse(home.input);
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('解析'),
                ),
              ),
              if (home.busy)
                TextButton(
                  onPressed: home.cancelParse,
                  child: const Text('取消解析'),
                ),
              ListenableBuilder(
                listenable: home.dependencies.favorites,
                builder: (context, _) {
                  final post = PostLink.tryParse(home.input);
                  final saved =
                      post != null &&
                      home.dependencies.favorites.items.any(
                        (f) => f.postId == post.postId,
                      );
                  return OutlinedButton.icon(
                    key: const Key('favorite_current'),
                    icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_add_outlined,
                    ),
                    label: Text(saved ? '已收藏' : '收藏'),
                    onPressed: post == null
                        ? null
                        : () => runAction(context, () async {
                            if (saved) {
                              await home.dependencies.favorites.remove(
                                post.postId,
                              );
                            } else {
                              await home.dependencies.favorites.add(
                                home.input,
                                title: home.result?.title,
                              );
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(saved ? '已取消收藏' : '已收藏链接'),
                                ),
                              );
                            }
                          }),
                  );
                },
              ),
            ],
          ),
          if (home.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(),
            ),
          if (home.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                home.error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ListenableBuilder(
            listenable: home.dependencies.sources,
            builder: (context, _) => Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SourcesScreen(
                      repository: home.dependencies.sources,
                      parser: home.dependencies.parser,
                      readClipboard: home.dependencies.readClipboard,
                    ),
                  ),
                ),
                icon: const Icon(Icons.dns_outlined),
                label: Text(
                  '解析源：${home.dependencies.sources.list.firstWhere((s) => s.id == home.dependencies.sources.currentId).name}',
                ),
              ),
            ),
          ),
          if (home.result != null)
            MediaResultView(
              result: home.result!,
              onDownload: (variant) async {
                await runAction(context, () async {
                  await home.download(variant);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已加入下载，可在下载页查看进度')),
                    );
                  }
                });
              },
            ),
          const SizedBox(height: 24),
          Text(
            '文件保存到 Download/XDownloader',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

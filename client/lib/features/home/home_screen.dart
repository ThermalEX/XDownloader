import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../app/favorite_icon.dart';
import '../../core/parsing/post_link.dart';
import '../settings/sources_screen.dart';
import 'home_controller.dart';
import 'media_result_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final HomeController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: [
        if (controller.busy) const LinearProgressIndicator(),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              controller.error!.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (controller.result != null)
          MediaResultView(
            result: controller.result!,
            onDownload: (variant) => runAction(context, () async {
              await controller.download(variant);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已加入下载，可在下载页查看进度')),
                );
              }
            }),
          ),
      ],
    ),
  );
}

class HomeComposer extends StatefulWidget {
  const HomeComposer({super.key, required this.controller});
  final HomeController controller;
  @override
  State<HomeComposer> createState() => _HomeComposerState();
}

class _HomeComposerState extends State<HomeComposer>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _keyboardVisible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final visible = View.of(context).viewInsets.bottom > 0;
    if (_keyboardVisible && !visible) _focus.unfocus();
    _keyboardVisible = visible;
  }

  void _focusChanged() {
    setState(() {});
    if (!_focus.hasFocus) _resetScroll();
  }

  void _resetScroll() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && !_focus.hasFocus && _scroll.hasClients) _scroll.jumpTo(0);
  });
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    _focus.unfocus();
    widget.controller.parse(widget.controller.input);
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
        _resetScroll();
      }
      final room =
          MediaQuery.sizeOf(context).height -
          MediaQuery.viewInsetsOf(context).bottom;
      final colors = Theme.of(context).colorScheme;
      final suffix = home.input.isEmpty
          ? Semantics(
              container: true,
              label: '从剪贴板粘贴',
              excludeSemantics: true,
              button: true,
              child: IconButton(
                tooltip: '粘贴',
                onPressed: () => runAction(context, home.paste),
                icon: const Icon(Icons.content_paste),
              ),
            )
          : IconButton(
              tooltip: '清空',
              onPressed: home.clear,
              icon: const Icon(Icons.close),
            );
      return PopScope(
        canPop: !_focus.hasFocus,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _focus.unfocus();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (room >= 240) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: HomeFavoriteAction(home: home),
                ),
                const SizedBox(height: 4),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextFieldTapRegion(
                      child: InputDecorator(
                        isFocused: _focus.hasFocus,
                        isEmpty: home.input.isEmpty,
                        decoration: InputDecoration(
                          labelText: '视频链接',
                          contentPadding: const EdgeInsets.fromLTRB(
                            16,
                            4,
                            4,
                            4,
                          ),
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final field = TextField(
                                    key: const Key('home_link_input'),
                                    focusNode: _focus,
                                    scrollController: _scroll,
                                    keyboardType: TextInputType.url,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    controller: _text,
                                    onChanged: home.setInput,
                                    onTapOutside: (_) => _focus.unfocus(),
                                    minLines: 1,
                                    maxLines:
                                        _focus.hasFocus &&
                                            MediaQuery.sizeOf(context).height >=
                                                500
                                        ? 3
                                        : 1,
                                    textInputAction: TextInputAction.go,
                                    onSubmitted: (_) => _parse(),
                                    decoration: null,
                                  );
                                  final measure = TextPainter(
                                    text: TextSpan(
                                      text: home.input.replaceAll('\n', ' '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    textDirection: TextDirection.ltr,
                                    maxLines: 1,
                                    textScaler: MediaQuery.textScalerOf(
                                      context,
                                    ),
                                  )..layout();
                                  final overflow =
                                      !_focus.hasFocus &&
                                      measure.width > constraints.maxWidth;
                                  measure.dispose();
                                  return ShaderMask(
                                    blendMode: BlendMode.dstIn,
                                    shaderCallback: (bounds) => LinearGradient(
                                      colors: [
                                        Colors.white,
                                        Colors.white,
                                        overflow
                                            ? Colors.transparent
                                            : Colors.white,
                                      ],
                                      stops: [0, .88, 1],
                                    ).createShader(bounds),
                                    child: field,
                                  );
                                },
                              ),
                            ),
                            suffix,
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    container: true,
                    label: home.busy ? '取消解析' : '解析链接',
                    excludeSemantics: true,
                    button: true,
                    child: IconButton.filledTonal(
                      tooltip: home.busy ? '取消解析' : '解析',
                      style: _homeActionStyle(context),
                      onPressed: home.busy ? home.cancelParse : _parse,
                      icon: Icon(home.busy ? Icons.close : Icons.search),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

ButtonStyle _homeActionStyle(BuildContext context) {
  final theme = Theme.of(context);
  return IconButton.styleFrom(
    minimumSize: const Size(56, 56),
    backgroundColor: Color.lerp(
      theme.colorScheme.secondaryContainer,
      Colors.white,
      theme.brightness == Brightness.dark ? .16 : .35,
    ),
    foregroundColor: theme.colorScheme.onSecondaryContainer,
  );
}

class HomeFavoriteAction extends StatelessWidget {
  const HomeFavoriteAction({super.key, required this.home});
  final HomeController home;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([home, home.dependencies.favorites]),
    builder: (context, _) {
      final post = PostLink.tryParse(home.input);
      final saved =
          post != null &&
          home.dependencies.favorites.items.any((f) => f.postId == post.postId);
      return IconButton.filledTonal(
        key: const Key('favorite_current'),
        tooltip: saved ? '已收藏，点击取消' : '收藏',
        isSelected: saved,
        icon: const Icon(Icons.favorite_border),
        selectedIcon: Icon(Icons.favorite, color: savedHeartColor(context)),
        style: _homeActionStyle(context),
        onPressed: post == null
            ? null
            : () => runAction(context, () async {
                if (saved) {
                  await home.dependencies.favorites.remove(post.postId);
                } else {
                  await home.dependencies.favorites.add(
                    home.input,
                    title: home.result?.title,
                  );
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(saved ? '已取消收藏' : '已收藏链接')),
                  );
                }
              }),
      );
    },
  );
}

class HomeSourceAction extends StatelessWidget {
  const HomeSourceAction({super.key, required this.controller});
  final HomeController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.dependencies.sources,
    builder: (context, _) {
      final dependencies = controller.dependencies;
      final name = dependencies.sources.list
          .firstWhere((s) => s.id == dependencies.sources.currentId)
          .name;
      return Tooltip(
        message: '解析源：$name',
        child: TextButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SourcesScreen(
                repository: dependencies.sources,
                parser: dependencies.parser,
                readClipboard: dependencies.readClipboard,
              ),
            ),
          ),
          icon: const Icon(Icons.dns_outlined, size: 20),
          label: const Text('解析源'),
        ),
      );
    },
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'favorite_icon.dart';
import '../core/models/app_failure.dart';
import '../features/home/home_controller.dart';
import '../features/home/home_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/settings/app_updates_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<AppShell> createState() => _ShellState();
}

class _ShellState extends State<AppShell> with WidgetsBindingObserver {
  late final HomeController home;
  StreamSubscription<String>? _shares;
  final _pages = PageController();
  int index = 0;
  @override
  void initState() {
    super.initState();
    home = HomeController(widget.dependencies);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.dependencies.updates.check(automatic: true));
      }
    });
  }

  Future<void> _listen() async {
    try {
      final initial = await widget.dependencies.shares.initialText();
      if (!mounted) return;
      _shares = widget.dependencies.shares.sharedText.listen(
        _share,
        onError: (Object e) {
          if (mounted) showError(context, e);
        },
      );
      if (initial != null) {
        _share(initial);
      } else {
        unawaited(home.onResumed());
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _share(String text) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      index = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
    home.setVisible(true);
    unawaited(home.acceptSharedText(text));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.dependencies.updates.refreshTransfer());
      unawaited(widget.dependencies.updates.check(automatic: true));
      unawaited(runAction(context, widget.dependencies.downloads.reconcile));
      unawaited(runAction(context, home.onResumed));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shares?.cancel());
    home.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.updates,
    builder: (context, _) => Scaffold(
      appBar:
          MediaQuery.viewInsetsOf(context).bottom > 0 &&
              MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom <
                  240
          ? null
          : AppBar(
              title: Text(['XDownloader', '下载', '收藏', '设置'][index]),
              actions: [
                if (index == 0) HomeSourceAction(controller: home),
                if (widget.dependencies.updates.result?.candidate != null)
                  IconButton(
                    tooltip: '发现新版本',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => AppUpdatesScreen(
                          repository: widget.dependencies.updates,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.system_update_outlined),
                  ),
              ],
            ),
      body: SafeArea(
        top:
            MediaQuery.viewInsetsOf(context).bottom > 0 &&
            MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom <
                240,
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: PageView(
              controller: _pages,
              onPageChanged: (value) {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => index = value);
                home.setVisible(value == 0);
              },
              children: [
                _PersistentPage(child: HomeScreen(controller: home)),
                _PersistentPage(
                  child: DownloadsScreen(
                    repository: widget.dependencies.downloads,
                    settings: widget.dependencies.settings,
                    onParse: _share,
                  ),
                ),
                _PersistentPage(
                  child: FavoritesScreen(
                    dependencies: widget.dependencies,
                    onOpen: _share,
                  ),
                ),
                _PersistentPage(
                  child: SettingsScreen(dependencies: widget.dependencies),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: switch (index) {
                    0 => HomeComposer(controller: home),
                    2 => FavoritesActions(dependencies: widget.dependencies),
                    _ => const SizedBox.shrink(),
                  },
                ),
              ),
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Theme(
                  data: Theme.of(context)
                      .copyWith(splashFactory: NoSplash.splashFactory),
                  child: NavigationBar(
                    animationDuration: const Duration(milliseconds: 250),
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? Colors.transparent
                          : null,
                    ),
                    selectedIndex: index,
                    onDestinationSelected: (value) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => index = value);
                      home.setVisible(value == 0);
                      _pages.jumpToPage(value);
                    },
                    destinations: [
                      const NavigationDestination(
                        key: Key('nav_home'),
                        icon: Icon(Icons.link),
                        label: '解析',
                      ),
                      const NavigationDestination(
                        key: Key('nav_downloads'),
                        icon: Icon(Icons.download_outlined),
                        label: '下载',
                      ),
                      NavigationDestination(
                        key: const Key('nav_favorites'),
                        icon: const Icon(Icons.favorite_border),
                        selectedIcon: Icon(
                          Icons.favorite,
                          color: savedHeartColor(context),
                        ),
                        label: '收藏',
                      ),
                      const NavigationDestination(
                        key: Key('nav_settings'),
                        icon: Icon(Icons.settings_outlined),
                        label: '设置',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PersistentPage extends StatefulWidget {
  const _PersistentPage({required this.child});
  final Widget child;
  @override
  State<_PersistentPage> createState() => _PersistentPageState();
}

class _PersistentPageState extends State<_PersistentPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error is AppFailure ? error.message : '操作未完成，请重试')),
  );
}

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

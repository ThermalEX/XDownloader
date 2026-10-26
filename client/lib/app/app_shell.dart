import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';

import 'bootstrap.dart';
import 'floating_actions_page.dart';
import 'handed_layout.dart';
import '../core/models/app_failure.dart';
import '../core/models/app_update.dart';
import '../features/home/home_controller.dart';
import '../features/home/home_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/settings/app_update_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<AppShell> createState() => _ShellState();
}

class _ShellState extends State<AppShell> with WidgetsBindingObserver {
  late final HomeController home;
  StreamSubscription<String>? _shares;
  final _pages = _NestedScrollPageController();
  ReleaseCheck? _pendingStartup;
  bool _promptScheduled = false;
  bool _backgrounded = false;
  bool _homeInitialized = false;
  bool _resumeHomePending = false;
  int index = 0;
  @override
  void initState() {
    super.initState();
    home = HomeController(widget.dependencies);
    WidgetsBinding.instance.addObserver(this);
    widget.dependencies.updates.addListener(_scheduleUpdatePrompt);
    widget.dependencies.updates.setForegroundVisible(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      owner: this,
    );
    unawaited(_listen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_checkAtStartup());
      }
    });
  }

  Future<void> _checkAtStartup() async {
    final updates = widget.dependencies.updates;
    final result = await updates.check(automatic: true);
    if (!mounted || result?.candidate == null) return;
    _pendingStartup = result;
    _scheduleUpdatePrompt();
  }

  void _scheduleUpdatePrompt() {
    if (!mounted ||
        (_pendingStartup == null &&
            !widget.dependencies.updates.needsInstallPrompt) ||
        _promptScheduled) {
      return;
    }
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      _showPendingUpdatePrompt();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showPendingUpdatePrompt() {
    if (!mounted) return;
    final updates = widget.dependencies.updates;
    if (ModalRoute.of(context)?.isCurrent != true ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    if (updates.needsInstallPrompt) {
      updates.acknowledgeInstallPrompt();
      _pendingStartup = null;
      unawaited(showUpdateInstallDialog(context, updates));
      return;
    }
    if (_pendingStartup == null) return;
    if (updates.transfer.active) {
      _pendingStartup = null;
      return;
    }
    if (!updates.preferences.autoCheck ||
        !updates.preferences.showUpdatePrompt ||
        !identical(_pendingStartup, updates.result)) {
      _pendingStartup = null;
      return;
    }
    // A newer check or channel change invalidates the accepted startup result.
    if (updates.checking) return;
    _pendingStartup = null;
    unawaited(showAppUpdateDialog(context, updates));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleUpdatePrompt();
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
      }
      await home.initializeClipboard();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      _homeInitialized = true;
      if (mounted &&
          _resumeHomePending &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(runAction(context, home.onResumed));
      }
      _resumeHomePending = false;
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

  void _openTab(int value) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => index = value);
    home.setVisible(value == 0);
    if (_pages.hasClients) _pages.jumpToPage(value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.dependencies.updates.setForegroundVisible(
      state == AppLifecycleState.resumed,
      owner: this,
    );
    if (!_backgrounded &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      _backgrounded = true;
      home.clear();
    }
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      _scheduleUpdatePrompt();
      unawaited(runAction(context, widget.dependencies.downloads.reconcile));
      if (_homeInitialized) {
        unawaited(runAction(context, home.onResumed));
      } else {
        _resumeHomePending = true;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dependencies.updates.removeListener(_scheduleUpdatePrompt);
    widget.dependencies.updates.setForegroundVisible(false, owner: this);
    unawaited(_shares?.cancel());
    home.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.dependencies.updates,
      widget.dependencies.settings,
    ]),
    builder: (context, _) => Scaffold(
      appBar:
          MediaQuery.viewInsetsOf(context).bottom > 0 &&
              MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom <
                  240
          ? null
          : HandedAppBar(
              enabled: index != 3,
              title: Text(['XDownloader', '下载', '收藏', '设置'][index]),
              actions: [
                if (index == 0) HomeSourceAction(controller: home),
                if (index == 0 &&
                    !widget.dependencies.settings.value.privacyMode)
                  IconButton(
                    key: const Key('home_quick_privacy'),
                    tooltip: '开启隐私模式',
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: () => runAction(
                      context,
                      () => widget.dependencies.settings.setPrivacyMode(true),
                    ),
                  ),
                if (widget.dependencies.updates.result?.candidate != null)
                  IconButton(
                    tooltip: '发现新版本',
                    onPressed: () => showAppUpdateDialog(
                      context,
                      widget.dependencies.updates,
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
        child: Column(
          children: [
            Expanded(
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
                      _PersistentPage(
                        child: FloatingActionsPage(
                          fadeKey: const Key('home_content_fade'),
                          content: HomeScreen(controller: home),
                          actions: HomeComposer(controller: home),
                        ),
                      ),
                      _PersistentPage(
                        child: DownloadsScreen(
                          repository: widget.dependencies.downloads,
                          favorites: widget.dependencies.favorites,
                          settings: widget.dependencies.settings,
                          onParse: _share,
                        ),
                      ),
                      _PersistentPage(
                        child: FloatingActionsPage(
                          fadeKey: const Key('favorites_content_fade'),
                          content: FavoritesScreen(
                            dependencies: widget.dependencies,
                            onOpen: _share,
                          ),
                          actions: FavoritesActions(
                            dependencies: widget.dependencies,
                          ),
                        ),
                      ),
                      _PersistentPage(
                        child: SettingsScreen(
                          dependencies: widget.dependencies,
                          onOpenTab: _openTab,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        bottom: MediaQuery.viewInsetsOf(context).bottom == 0,
        child: AnimatedSize(
          key: const Key('root_navigation_transition'),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: MediaQuery.viewInsetsOf(context).bottom > 0
              ? const SizedBox(width: double.infinity, height: 0)
              : Theme(
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
                      const NavigationDestination(
                        key: Key('nav_favorites'),
                        icon: Icon(Icons.favorite_border),
                        selectedIcon: Icon(Icons.favorite),
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
        ),
      ),
    ),
  );
}

// Retain the SDK page position's snapping, restoration and semantics, while
// allowing a new gesture to reach nested scrollers during page animations.
class _NestedScrollPageController extends PageController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    final previous = oldPosition?.context;
    // Absorbing a position after a theme/physics change requires the same context.
    final interactive =
        previous is _InteractiveScrollContext &&
            identical(previous.delegate, context)
        ? previous
        : _InteractiveScrollContext(context);
    return super.createScrollPosition(physics, interactive, oldPosition);
  }
}

class _InteractiveScrollContext implements ScrollContext {
  const _InteractiveScrollContext(this.delegate);
  final ScrollContext delegate;
  @override
  BuildContext? get notificationContext => delegate.notificationContext;
  @override
  BuildContext get storageContext => delegate.storageContext;
  @override
  TickerProvider get vsync => delegate.vsync;
  @override
  AxisDirection get axisDirection => delegate.axisDirection;
  @override
  double get devicePixelRatio => delegate.devicePixelRatio;
  @override
  void setIgnorePointer(bool value) => delegate.setIgnorePointer(false);
  @override
  void setCanDrag(bool value) => delegate.setCanDrag(value);
  @override
  void setSemanticsActions(Set<SemanticsAction> actions) =>
      delegate.setSemanticsActions(actions);
  @override
  void saveOffset(double offset) => delegate.saveOffset(offset);
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

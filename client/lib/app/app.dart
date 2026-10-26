import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dynamic_palette.dart';

import 'bootstrap.dart';
import 'app_theme.dart';
import 'app_shell.dart';
import 'handed_layout.dart';
import '../core/models/app_settings.dart';
import '../data/repositories/update_repository.dart';

class XDownloaderApp extends StatefulWidget {
  const XDownloaderApp({super.key, this.dependencies, this.palette});
  final AppDependencies? dependencies;
  final Future<DynamicPalette>? palette;
  @override
  State<XDownloaderApp> createState() => _AppState();
}

class _AppState extends State<XDownloaderApp> {
  late Future<(AppDependencies, DynamicPalette)> _loading;
  UpdateRepository? _ownedUpdates;
  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<(AppDependencies, DynamicPalette)> _load() async {
    final colors = (widget.palette ?? loadDynamicPalette()).catchError(
      (Object _) => const DynamicPalette(),
    );
    final dependencies = widget.dependencies == null
        ? bootstrap()
        : Future.value(widget.dependencies!);
    final loaded = await dependencies;
    if (widget.dependencies == null) {
      if (mounted) {
        _ownedUpdates = loaded.updates;
      } else {
        loaded.updates.dispose();
      }
    }
    return (loaded, await colors);
  }

  @override
  void dispose() {
    _ownedUpdates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<(AppDependencies, DynamicPalette)>(
        future: _loading,
        builder: (context, snapshot) {
          final deps = snapshot.data?.$1;
          if (deps == null) {
            return MaterialApp(
              key: const ValueKey('bootstrap'),
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.grey,
                  brightness: Brightness.dark,
                ),
              ),
              home: Scaffold(
                body: Center(
                  child: snapshot.hasError
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('无法读取应用数据，原文件已保留'),
                              Text('${snapshot.error}'),
                              TextButton(
                                onPressed: () => setState(() {
                                  _loading = _load();
                                }),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            );
          }
          return ListenableBuilder(
            listenable: deps.settings,
            builder: (context, _) {
              final settings = deps.settings.value;
              Widget app(ColorScheme? light, ColorScheme? dark) => MaterialApp(
                key: const ValueKey('ready'),
                title: 'XDownloader',
                builder: (context, child) => HandedLayout(
                  handedness: settings.handedness,
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: AppTheme.systemBars(Theme.of(context).brightness),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                debugShowCheckedModeBanner: false,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
                locale: const Locale('zh', 'CN'),
                themeMode: switch (settings.themeMode) {
                  AppThemeMode.system => ThemeMode.system,
                  AppThemeMode.light => ThemeMode.light,
                  AppThemeMode.dark => ThemeMode.dark,
                },
                theme: AppTheme.build(
                  settings,
                  Brightness.light,
                  dynamicScheme: settings.useDynamicColor ? light : null,
                ),
                darkTheme: AppTheme.build(
                  settings,
                  Brightness.dark,
                  dynamicScheme: settings.useDynamicColor ? dark : null,
                ),
                home: AppShell(dependencies: deps),
              );
              return app(snapshot.data!.$2.light, snapshot.data!.$2.dark);
            },
          );
        },
      );
}

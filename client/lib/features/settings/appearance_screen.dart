import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/models/app_settings.dart';
import '../../data/repositories/settings_repository.dart';
import 'settings_group.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.repository});
  final SettingsRepository repository;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('外观')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final value = repository.value;
          void edit(AppSettings Function(AppSettings) transform) =>
              runAction(context, () => repository.edit(transform));
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              SettingsPanel(
                title: '主题模式',
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<AppThemeMode>(
                    borderRadius: BorderRadius.circular(20),
                    key: const Key('theme_mode'),
                    initialValue: value.themeMode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '主题模式'),
                    items: const [
                      DropdownMenuItem(
                        value: AppThemeMode.system,
                        child: Text('跟随系统'),
                      ),
                      DropdownMenuItem(
                        value: AppThemeMode.light,
                        child: Text('浅色'),
                      ),
                      DropdownMenuItem(
                        value: AppThemeMode.dark,
                        child: Text('深色'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) edit((s) => s.copyWith(themeMode: v));
                    },
                  ),
                ),
              ),
              SettingsPanel(
                title: '主题颜色',
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('选择预设颜色，或开启下方的动态取色。'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final color in const [
                            (seed: 0xFF4F6F52, label: '森林绿', tooltip: '绿色主题'),
                            (seed: 0xFF47658A, label: '湖蓝', tooltip: '蓝色主题'),
                            (seed: 0xFF77558A, label: '雾紫', tooltip: '紫色主题'),
                            (seed: 0xFF8C5362, label: '玫瑰', tooltip: '玫瑰主题'),
                          ])
                            Tooltip(
                              message: color.tooltip,
                              child: ChoiceChip(
                                label: Text(color.label),
                                avatar: Icon(
                                  Icons.circle,
                                  color: Color(color.seed),
                                  size: 20,
                                ),
                                selected:
                                    value.seedColor == color.seed &&
                                    !value.useDynamicColor,
                                onSelected: (_) => edit(
                                  (s) => s.copyWith(
                                    seedColor: color.seed,
                                    useDynamicColor: false,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SettingsPanel(
                title: '系统配色',
                child: SwitchListTile(
                  title: const Text('动态取色'),
                  subtitle: const Text('使用系统壁纸配色，不支持时使用主题色'),
                  value: value.useDynamicColor,
                  onChanged: (v) => edit((s) => s.copyWith(useDynamicColor: v)),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

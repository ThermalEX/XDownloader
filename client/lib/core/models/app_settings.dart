import '../naming/file_naming.dart';

enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seedColor = 0xFF4F6F52,
    this.useDynamicColor = false,
    this.autoClipboard = true,
    this.privacyMode = false,
    this.playfulAvatar = false,
    this.useOriginalFileName = false,
    this.fileNameTemplate = FileNaming.defaultTemplate,
  });
  final AppThemeMode themeMode;
  final int seedColor;
  final bool useDynamicColor, autoClipboard;
  final bool privacyMode, useOriginalFileName;
  final bool playfulAvatar;
  final String fileNameTemplate;
  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? seedColor,
    bool? useDynamicColor,
    bool? autoClipboard,
    bool? privacyMode,
    bool? playfulAvatar,
    bool? useOriginalFileName,
    String? fileNameTemplate,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    seedColor: seedColor ?? this.seedColor,
    useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    autoClipboard: autoClipboard ?? this.autoClipboard,
    privacyMode: privacyMode ?? this.privacyMode,
    playfulAvatar: playfulAvatar ?? this.playfulAvatar,
    useOriginalFileName: useOriginalFileName ?? this.useOriginalFileName,
    fileNameTemplate: fileNameTemplate ?? this.fileNameTemplate,
  );
  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'seedColor': seedColor,
    'useDynamicColor': useDynamicColor,
    'autoClipboard': autoClipboard,
    'privacyMode': privacyMode,
    'playfulAvatar': playfulAvatar,
    'useOriginalFileName': useOriginalFileName,
    'fileNameTemplate': fileNameTemplate,
  };
  factory AppSettings.fromJson(Map<String, Object?> m) => AppSettings(
    themeMode:
        AppThemeMode.values
            .where((v) => v.name == m['themeMode'])
            .firstOrNull ??
        AppThemeMode.system,
    seedColor: (m['seedColor'] as num?)?.toInt() ?? 0xFF4F6F52,
    useDynamicColor: m['useDynamicColor'] == true,
    autoClipboard: m['autoClipboard'] != false,
    privacyMode: m['privacyMode'] == true,
    playfulAvatar: m['playfulAvatar'] == true,
    useOriginalFileName: m['useOriginalFileName'] == true,
    fileNameTemplate:
        m['fileNameTemplate'] as String? ?? FileNaming.defaultTemplate,
  );
}

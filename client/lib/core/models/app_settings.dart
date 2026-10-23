import '../naming/file_naming.dart';
import '../security/privacy_password.dart';

enum AppThemeMode { system, light, dark }

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.seedColor = 0xFF4F6F52,
    this.useDynamicColor = false,
    this.autoClipboard = true,
    this.privacyMode = false,
    this.privacyPasswordHash = '',
    this.playfulAvatar = false,
    this.coverCacheLimitMb = 100,
    this.useOriginalFileName = false,
    this.fileNameTemplate = FileNaming.defaultTemplate,
  });
  final AppThemeMode themeMode;
  final int seedColor;
  final bool useDynamicColor, autoClipboard;
  final bool privacyMode, useOriginalFileName;
  final bool playfulAvatar;
  final int coverCacheLimitMb;
  final String fileNameTemplate;
  final String privacyPasswordHash;
  AppSettings copyWith({
    AppThemeMode? themeMode,
    int? seedColor,
    bool? useDynamicColor,
    bool? autoClipboard,
    bool? privacyMode,
    String? privacyPasswordHash,
    bool? playfulAvatar,
    int? coverCacheLimitMb,
    bool? useOriginalFileName,
    String? fileNameTemplate,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    seedColor: seedColor ?? this.seedColor,
    useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    autoClipboard: autoClipboard ?? this.autoClipboard,
    privacyMode: privacyMode ?? this.privacyMode,
    privacyPasswordHash: privacyPasswordHash ?? this.privacyPasswordHash,
    playfulAvatar: playfulAvatar ?? this.playfulAvatar,
    coverCacheLimitMb: coverCacheLimitMb ?? this.coverCacheLimitMb,
    useOriginalFileName: useOriginalFileName ?? this.useOriginalFileName,
    fileNameTemplate: fileNameTemplate ?? this.fileNameTemplate,
  );
  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'seedColor': seedColor,
    'useDynamicColor': useDynamicColor,
    'autoClipboard': autoClipboard,
    'privacyMode': privacyMode,
    'privacyPasswordHash': privacyPasswordHash,
    'playfulAvatar': playfulAvatar,
    'coverCacheLimitMb': coverCacheLimitMb,
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
    privacyPasswordHash: _passwordHash(m['privacyPasswordHash']),
    playfulAvatar: m['playfulAvatar'] == true,
    coverCacheLimitMb: _cacheLimit(m['coverCacheLimitMb']),
    useOriginalFileName: m['useOriginalFileName'] == true,
    fileNameTemplate:
        m['fileNameTemplate'] as String? ?? FileNaming.defaultTemplate,
  );
}

String _passwordHash(Object? value) {
  if (value == null) return '';
  if (value is! String || !PrivacyPasswords.validHash(value)) {
    throw const FormatException('Invalid privacy password verifier');
  }
  return value;
}

int _cacheLimit(Object? value) {
  if (value == null) return 100;
  if (value is! int || value < 0 || value > 2048) {
    throw const FormatException('Invalid cover cache limit');
  }
  return value;
}

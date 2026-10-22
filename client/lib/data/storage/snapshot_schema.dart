import '../../core/models/app_settings.dart';
import '../../core/models/app_update.dart';
import '../../core/models/download.dart';
import '../../core/models/download_history.dart';
import '../../core/models/source.dart';
import '../../core/models/favorite_link.dart';
import '../../core/naming/file_naming.dart';

/// Schema v1 validation applies equally to current and backup candidates.
/// Unknown fields are retained for compatibility; known fields must decode.
class SnapshotSchema {
  static bool accepts(String key, Map<String, Object?> data) {
    try {
      switch (key) {
        case 'updates':
          UpdatePreferences.fromJson(data);
        case 'settings':
          AppSettings.fromJson(data);
          if (data['themeMode'] != null && data['themeMode'] is! String) {
            return false;
          }
          if (!_bool(data['useDynamicColor']) ||
              !_bool(data['autoClipboard']) ||
              !_bool(data['privacyMode']) ||
              !_bool(data['useOriginalFileName'])) {
            return false;
          }
          if (data['fileNameTemplate'] != null &&
              (data['fileNameTemplate'] is! String ||
                  FileNaming.validateTemplate(
                        data['fileNameTemplate'] as String,
                      ) !=
                      null)) {
            return false;
          }
        case 'favorites':
          if (data['sort'] != null &&
              !const [
                'defaultOrder',
                'newest',
                'oldest',
                'title',
              ].contains(data['sort'])) {
            return false;
          }
          final ids = <String>{};
          for (final raw in data['items'] as List? ?? []) {
            final favorite = FavoriteLink.fromJson(
              Map<String, Object?>.from(raw as Map),
            );
            if (!ids.add(favorite.postId)) return false;
          }
        case 'sources':
          if (data['current'] != null && data['current'] is! String) {
            return false;
          }
          if (!_bool(data['fallback'])) return false;
          for (final raw in data['custom'] as List? ?? []) {
            ParseSource.fromJson(Map<String, dynamic>.from(raw as Map));
          }
        case 'downloads':
          if (data['historyVersion'] != null && data['historyVersion'] != 1) {
            return false;
          }
          final historyIds = <String>{};
          for (final raw in data['history'] as List? ?? []) {
            final entry = DownloadHistoryEntry.fromJson(
              Map<String, Object?>.from(raw as Map),
            );
            if (!historyIds.add(entry.taskId)) return false;
          }
          for (final id in data['historySuppressed'] as List? ?? []) {
            if (id is! String) return false;
          }
          for (final raw in data['records'] as List? ?? []) {
            DownloadRecord.fromJson(Map<String, dynamic>.from(raw as Map));
          }
          for (final id in data['ignored'] as List? ?? []) {
            if (id is! String) return false;
          }
        case 'migration':
          if (!_bool(data['completed'])) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool _bool(Object? value) => value == null || value is bool;
}

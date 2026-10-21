import '../core/models/download.dart';
import 'platform_bridge.dart';

class LegacySnapshot {
  LegacySnapshot({
    required Map<String, Object?> sources,
    required Map<String, Object?> settings,
    this.historyJson,
  }) : sources = Map.unmodifiable(sources),
       settings = Map.unmodifiable(settings);
  final Map<String, Object?> sources, settings;
  final String? historyJson;
}

class LegacyDataGateway {
  LegacyDataGateway({PlatformCall? call}) : call = call ?? callPlatform;
  final PlatformCall call;
  Future<LegacySnapshot> read() async {
    final m = Map<String, dynamic>.from(await call('readLegacy', {}) as Map);
    return LegacySnapshot(
      sources: Map<String, Object?>.from(m['sources'] as Map? ?? {}),
      settings: Map<String, Object?>.from(m['settings'] as Map? ?? {}),
      historyJson: m['historyJson'] as String?,
    );
  }

  Future<SavedFile?> locateOwnedDownload(String displayName) async {
    final value = await call('locateOwnedDownload', {
      'displayName': displayName,
    });
    return value == null
        ? null
        : SavedFile.fromJson(Map<String, dynamic>.from(value as Map));
  }
}

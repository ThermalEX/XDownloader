enum UpdateChannel { stable, beta }

class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.sdkInt,
    required this.supportedAbis,
  });
  final String packageName, versionName;
  final int versionCode, sdkInt;
  final List<String> supportedAbis;
  factory InstalledAppInfo.fromJson(Map<String, Object?> m) => InstalledAppInfo(
    packageName: m['packageName'] as String,
    versionName: m['versionName'] as String,
    versionCode: m['versionCode'] as int,
    sdkInt: m['sdkInt'] as int,
    supportedAbis: List<String>.from(m['supportedAbis'] as List),
  );
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.abis,
    required this.bytes,
    required this.sha256,
  });
  static const maxBytes = 200 * 1024 * 1024;
  final String name, sha256;
  final Uri url;
  final List<String> abis;
  final int bytes;
  Map<String, Object?> toJson() => {
    'name': name,
    'url': url.toString(),
    'abis': abis,
    'bytes': bytes,
    'sha256': sha256,
  };
  factory UpdateAsset.fromJson(Map<String, Object?> m) {
    final name = m['name'] as String,
        bytes = m['bytes'] as int,
        hash = m['sha256'] as String;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*\.apk$').hasMatch(name) ||
        bytes <= 0 ||
        bytes > maxBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid update asset');
    }
    final abis = List<String>.from(m['abis'] as List);
    if (abis.isEmpty ||
        abis.any(
          (a) =>
              !const ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'].contains(a),
        ) ||
        abis.toSet().length != abis.length) {
      throw const FormatException('Invalid update ABI');
    }
    return UpdateAsset(
      name: name,
      url: Uri.parse(m['url'] as String),
      abis: List.unmodifiable(abis),
      bytes: bytes,
      sha256: hash,
    );
  }
}

class UpdateRelease {
  const UpdateRelease({
    required this.releaseId,
    required this.tag,
    required this.releasePage,
    required this.notes,
    this.title = '',
    required this.versionName,
    required this.versionCode,
    required this.channel,
    required this.packageName,
    required this.minSdk,
    required this.assets,
  });
  final int releaseId, versionCode, minSdk;
  final String tag, notes, title, versionName, packageName;
  final Uri releasePage;
  final UpdateChannel channel;

  /// Compatible assets in preference order; first is the download choice.
  final List<UpdateAsset> assets;
  String get displayTitle =>
      title.trim().isEmpty ? 'XDownloader $versionName' : title.trim();
  String get displayNotes {
    final lines = notes.split(RegExp(r'\r?\n'));
    var first = 0;
    while (first < lines.length && lines[first].trim().isEmpty) {
      first++;
    }
    if (first == lines.length) return notes;
    final heading = RegExp(r'^ {0,3}#{1,6}[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$')
        .firstMatch(lines[first]);
    if (heading == null ||
        !{
          displayTitle,
          'XDownloader $versionName',
          versionName,
          'v$versionName',
        }.contains(heading[1]!.trim())) {
      return notes;
    }
    first++;
    while (first < lines.length && lines[first].trim().isEmpty) {
      first++;
    }
    return lines.skip(first).join('\n');
  }

  String get candidateId => '$releaseId:$versionCode:${assets.first.sha256}';
  Map<String, Object?> toJson() => {
    'candidateId': candidateId,
    'releaseId': releaseId,
    'tag': tag,
    'releasePage': releasePage.toString(),
    'notes': notes,
    'title': title,
    'versionName': versionName,
    'versionCode': versionCode,
    'channel': channel.name,
    'packageName': packageName,
    'minSdk': minSdk,
    'assets': assets.map((a) => a.toJson()).toList(),
  };
}

class ReleaseCheck {
  const ReleaseCheck({
    this.candidate,
    required this.scopeComplete,
    required this.skippedReleases,
    required this.validReleases,
  });
  final UpdateRelease? candidate;
  final bool scopeComplete;
  final int skippedReleases, validReleases;
}

class UpdatePreferences {
  const UpdatePreferences({
    this.channel = UpdateChannel.stable,
    this.autoCheck = true,
    this.showUpdatePrompt = true,
    this.lastAutomaticCheckAt,
  });
  final UpdateChannel channel;
  final bool autoCheck;
  final bool showUpdatePrompt;
  final DateTime? lastAutomaticCheckAt;
  UpdatePreferences copyWith({
    UpdateChannel? channel,
    bool? autoCheck,
    bool? showUpdatePrompt,
    DateTime? lastAutomaticCheckAt,
  }) => UpdatePreferences(
    channel: channel ?? this.channel,
    autoCheck: autoCheck ?? this.autoCheck,
    showUpdatePrompt: showUpdatePrompt ?? this.showUpdatePrompt,
    lastAutomaticCheckAt: lastAutomaticCheckAt ?? this.lastAutomaticCheckAt,
  );
  Map<String, Object?> toJson() => {
    'channel': channel.name,
    'autoCheck': autoCheck,
    'showUpdatePrompt': showUpdatePrompt,
    'lastAutomaticCheckAt': lastAutomaticCheckAt?.toUtc().toIso8601String(),
  };
  factory UpdatePreferences.fromJson(Map<String, Object?> m) =>
      UpdatePreferences(
        channel: m['channel'] == null
            ? UpdateChannel.stable
            : UpdateChannel.values.byName(m['channel'] as String),
        autoCheck: m['autoCheck'] == null ? true : m['autoCheck'] as bool,
        showUpdatePrompt: m['showUpdatePrompt'] == null
            ? true
            : m['showUpdatePrompt'] as bool,
        lastAutomaticCheckAt: m['lastAutomaticCheckAt'] == null
            ? null
            : DateTime.parse(m['lastAutomaticCheckAt'] as String),
      );
}

enum UpdatePhase {
  idle,
  queued,
  running,
  verifying,
  ready,
  permissionRequired,
  failed,
  cancelled,
}

class UpdateTransfer {
  const UpdateTransfer({
    this.versionName,
    this.versionCode,
    this.candidateId,
    this.phase = UpdatePhase.idle,
    this.bytes = 0,
    this.totalBytes,
    this.error,
  });
  final String? candidateId, error;
  final String? versionName;
  final int? versionCode;
  final UpdatePhase phase;
  final int bytes;
  final int? totalBytes;
  bool get active => const [
    UpdatePhase.queued,
    UpdatePhase.running,
    UpdatePhase.verifying,
    UpdatePhase.ready,
    UpdatePhase.permissionRequired,
  ].contains(phase);
  factory UpdateTransfer.fromJson(Map<String, Object?> m) => UpdateTransfer(
    versionName: m['versionName'] as String?,
    versionCode: m['versionCode'] as int?,
    candidateId: m['candidateId'] as String?,
    phase: UpdatePhase.values.byName(m['phase'] as String),
    bytes: m['bytes'] as int? ?? 0,
    totalBytes: m['totalBytes'] as int?,
    error: m['error'] as String?,
  );
}

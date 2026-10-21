import 'app_failure.dart';

class DownloadRequest {
  const DownloadRequest({
    required this.taskId,
    required this.url,
    required this.displayName,
    required this.headers,
    required this.mediaIndex,
    this.postUrl,
    this.width,
    this.height,
  });
  final String taskId;
  final Uri url;
  final String displayName;
  final Map<String, String> headers;
  final int mediaIndex;
  final Uri? postUrl;
  final int? width, height;
  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'url': url.toString(),
    'displayName': displayName,
    'headers': headers,
    'mediaIndex': mediaIndex,
    'postUrl': postUrl?.toString(),
    'width': width,
    'height': height,
  };
  factory DownloadRequest.fromJson(Map<String, dynamic> m) => DownloadRequest(
    taskId: m['taskId'] as String,
    url: Uri.parse(m['url'] as String),
    displayName: m['displayName'] as String,
    headers: Map<String, String>.from(m['headers'] as Map? ?? {}),
    mediaIndex: (m['mediaIndex'] as num?)?.toInt() ?? 1,
    postUrl: m['postUrl'] == null ? null : Uri.parse(m['postUrl'] as String),
    width: (m['width'] as num?)?.toInt(),
    height: (m['height'] as num?)?.toInt(),
  );
  DownloadRequest withId(String id) => DownloadRequest(
    taskId: id,
    url: url,
    displayName: displayName,
    headers: headers,
    mediaIndex: mediaIndex,
    postUrl: postUrl,
    width: width,
    height: height,
  );
}

enum DownloadPhase {
  queued,
  running,
  publishing,
  completed,
  failed,
  cancelled;

  bool get terminal => this == completed || this == failed || this == cancelled;
}

class DownloadRecord {
  DownloadRecord({
    required this.request,
    required this.phase,
    required this.createdAt,
    DateTime? updatedAt,
    this.savedFile,
    this.error,
    this.legacy = false,
    this.bytes = 0,
    this.totalBytes,
  }) : updatedAt = updatedAt ?? createdAt;
  final DownloadRequest request;
  final DownloadPhase phase;
  final SavedFile? savedFile;
  final AppFailure? error;
  final DateTime createdAt, updatedAt;
  final bool legacy;
  final int bytes;
  final int? totalBytes;
  String get taskId => request.taskId;
  DownloadRecord copyWith({
    DownloadPhase? phase,
    SavedFile? savedFile,
    AppFailure? error,
    bool clearError = false,
    int? bytes,
    int? totalBytes,
  }) => DownloadRecord(
    request: request,
    phase: phase ?? this.phase,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    savedFile: savedFile ?? this.savedFile,
    error: clearError ? null : error ?? this.error,
    legacy: legacy,
    bytes: bytes ?? this.bytes,
    totalBytes: totalBytes ?? this.totalBytes,
  );
  Map<String, Object?> toJson() => {
    'request': request.toJson(),
    'phase': phase.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'savedFile': savedFile?.toJson(),
    'legacy': legacy,
    'bytes': bytes,
    'totalBytes': totalBytes,
    'error': error == null
        ? null
        : {
            'kind': error!.kind.name,
            'message': error!.message,
            'details': error!.details,
          },
  };
  factory DownloadRecord.fromJson(Map<String, dynamic> m) {
    final e = m['error'] as Map?;
    return DownloadRecord(
      request: DownloadRequest.fromJson(
        Map<String, dynamic>.from(m['request'] as Map),
      ),
      phase: DownloadPhase.values.byName(m['phase'] as String),
      createdAt: DateTime.parse(m['createdAt'] as String),
      updatedAt: DateTime.parse(m['updatedAt'] as String),
      savedFile: m['savedFile'] == null
          ? null
          : SavedFile.fromJson(
              Map<String, dynamic>.from(m['savedFile'] as Map),
            ),
      error: e == null
          ? null
          : AppFailure(
              FailureKind.values.byName(e['kind'] as String),
              e['message'] as String,
              e['details'] as String?,
            ),
      legacy: m['legacy'] == true,
      bytes: (m['bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (m['totalBytes'] as num?)?.toInt(),
    );
  }
}

enum BackendPhase { queued, running, transferred, failed, cancelled }

class SavedFile {
  const SavedFile({
    required this.locator,
    required this.displayName,
    required this.bytes,
    required this.mimeType,
  });
  final String locator, displayName, mimeType;
  final int bytes;
  factory SavedFile.fromJson(Map<String, dynamic> json) => SavedFile(
    locator: json['locator'] as String,
    displayName: json['displayName'] as String,
    bytes: (json['bytes'] as num).toInt(),
    mimeType: json['mimeType'] as String,
  );
  Map<String, Object?> toJson() => {
    'locator': locator,
    'displayName': displayName,
    'bytes': bytes,
    'mimeType': mimeType,
  };
}

class BackendTaskSnapshot {
  const BackendTaskSnapshot({
    required this.taskId,
    required this.phase,
    required this.bytes,
    this.totalBytes,
    this.stagingPath,
    this.error,
    this.savedFile,
    this.request,
  });
  final String taskId;
  final BackendPhase phase;
  final int bytes;
  final int? totalBytes;
  final String? stagingPath;
  final AppFailure? error;
  final SavedFile? savedFile;
  final DownloadRequest? request;
}

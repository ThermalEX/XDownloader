import 'download.dart';

/// A durable source reference, independent of the saved file and transfer URL.
class DownloadHistoryEntry {
  const DownloadHistoryEntry({
    required this.taskId,
    required this.displayName,
    required this.postUrl,
    required this.createdAt,
    required this.finishedAt,
    required this.phase,
  });
  final String taskId, displayName;
  final Uri? postUrl;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final DownloadPhase phase;

  factory DownloadHistoryEntry.fromRecord(
    DownloadRecord record, {
    DateTime? finishedAt,
  }) => DownloadHistoryEntry(
    taskId: record.taskId,
    displayName: record.request.displayName,
    postUrl: record.request.postUrl,
    createdAt: record.createdAt,
    finishedAt: record.phase.terminal ? finishedAt ?? record.updatedAt : null,
    phase: record.phase,
  );
  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'displayName': displayName,
    'postUrl': postUrl?.toString(),
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'phase': phase.name,
  };
  factory DownloadHistoryEntry.fromJson(Map<String, Object?> json) {
    final id = json['taskId'] as String;
    if (id.isEmpty) throw const FormatException('Empty history identity');
    return DownloadHistoryEntry(
      taskId: id,
      displayName: json['displayName'] as String,
      postUrl: json['postUrl'] == null
          ? null
          : Uri.parse(json['postUrl'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      phase: DownloadPhase.values.byName(json['phase'] as String),
    );
  }
}

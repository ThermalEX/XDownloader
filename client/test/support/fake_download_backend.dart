import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/platform/download_backend.dart';

class FakeDownloadBackend implements DownloadBackend {
  FakeDownloadBackend(this.directory);
  final Directory directory;
  final events = StreamController<BackendTaskSnapshot>.broadcast(sync: true);
  final state = <String, BackendTaskSnapshot>{};
  final enqueued = <DownloadRequest>[];
  final saved = <String, SavedFile>{};
  bool failPublication = false;
  bool failDeletion = false;
  final failDeletionFor = <String>{};
  Future<void> Function()? afterPublication;
  int publications = 0;
  void emit(BackendTaskSnapshot s) {
    state[s.taskId] = s;
    events.add(s);
  }

  @override
  Stream<BackendTaskSnapshot> get updates => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> enqueue(DownloadRequest r) async {
    enqueued.add(r);
    emit(
      BackendTaskSnapshot(
        taskId: r.taskId,
        phase: BackendPhase.queued,
        bytes: 0,
      ),
    );
  }

  @override
  Future<void> cancel(String id) async => emit(
    BackendTaskSnapshot(taskId: id, phase: BackendPhase.cancelled, bytes: 0),
  );
  @override
  Future<List<BackendTaskSnapshot>> snapshot() async => state.values.toList();
  @override
  Future<SavedFile> publish(String id) async {
    if (failPublication) throw const AppFailure(FailureKind.storage, '磁盘空间不足');
    if (saved.containsKey(id)) return saved[id]!;
    publications++;
    final file = await File('${directory.path}/$id.mp4')
        .writeAsBytes([0, 0, 0, 8, 102, 116, 121, 112], flush: true);
    final receipt = saved[id] = SavedFile(
      locator: file.path,
      displayName: '$id.mp4',
      bytes: 8,
      mimeType: 'video/mp4',
    );
    await afterPublication?.call();
    return receipt;
  }

  @override
  Future<void> open(SavedFile f) async {
    await ensureReadable(f);
  }

  @override
  Future<void> ensureReadable(SavedFile f) async {
    if (!await File(f.locator).exists()) {
      throw const AppFailure(FailureKind.fileMissing, '文件不存在');
    }
  }

  @override
  Future<Uint8List?> thumbnailSavedFile(SavedFile f) async => null;

  @override
  Future<void> deleteSavedFile(SavedFile f) async {
    if (failDeletion || failDeletionFor.contains(f.locator)) {
      throw const AppFailure(FailureKind.storage, '无法删除文件');
    }
    if (Uri.parse(f.locator).scheme != 'content') {
      final file = File(f.locator);
      if (await file.exists()) await file.delete();
    }
    saved.removeWhere((_, value) => value.locator == f.locator);
  }

  @override
  Future<void> discardStaging(String id) async {}
  @override
  Future<void> openDirectory() async {}
  Future<void> close() => events.close();
}

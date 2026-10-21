import 'dart:math';
import 'dart:typed_data';

import '../core/models/download.dart';

String newTaskId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

abstract interface class DownloadBackend {
  Stream<BackendTaskSnapshot> get updates;
  Future<void> initialize();
  Future<void> enqueue(DownloadRequest request);
  Future<void> cancel(String taskId);
  Future<List<BackendTaskSnapshot>> snapshot();
  Future<SavedFile> publish(String taskId);
  Future<void> discardStaging(String taskId);
  Future<void> open(SavedFile file);
  Future<void> ensureReadable(SavedFile file);
  Future<Uint8List?> thumbnailSavedFile(SavedFile file);
  Future<void> deleteSavedFile(SavedFile file);
  Future<void> openDirectory();
}

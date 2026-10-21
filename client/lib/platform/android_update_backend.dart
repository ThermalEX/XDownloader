import 'package:flutter/services.dart';

import '../core/models/app_failure.dart';
import '../core/models/app_update.dart';
import 'platform_bridge.dart';
import 'update_backend.dart';

class AndroidUpdateBackend implements UpdateBackend {
  AndroidUpdateBackend({PlatformCall? call}) : call = call ?? callPlatform;
  final PlatformCall call;
  Future<Object?> _call(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      return await call(method, arguments);
    } on PlatformException catch (e) {
      throw AppFailure(FailureKind.storage, e.message ?? '无法完成应用更新');
    }
  }

  Future<T> _decode<T>(
    String method,
    T Function(Map<String, Object?>) decode, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final value = await _call(method, arguments);
    try {
      return decode(Map<String, Object?>.from(value as Map));
    } catch (_) {
      throw const AppFailure(FailureKind.malformed, '无法读取系统更新状态，请重试');
    }
  }

  @override
  Future<InstalledAppInfo> installedApp() =>
      _decode('updateInstalledApp', InstalledAppInfo.fromJson);
  @override
  Future<UpdateTransfer> snapshot() =>
      _decode('updateSnapshot', UpdateTransfer.fromJson);
  @override
  Future<void> enqueue(UpdateRelease release, UpdateAsset asset) async {
    await _call('updateEnqueue', {
      ...release.toJson(),
      'asset': asset.toJson(),
    });
  }

  @override
  Future<void> cancel(String candidateId) async {
    await _call('updateCancel', {'candidateId': candidateId});
  }

  @override
  Future<UpdateTransfer> requestInstall(String candidateId) => _decode(
    'updateInstall',
    UpdateTransfer.fromJson,
    {'candidateId': candidateId},
  );
  @override
  Future<void> openReleasePage(Uri url) async {
    await _call('updateOpenReleasePage', {'url': url.toString()});
  }
}

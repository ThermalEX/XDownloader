import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/app_update.dart';
import '../../platform/update_backend.dart';
import '../storage/serial_queue.dart';
import '../storage/snapshot_store.dart';
import '../updates/github_release_client.dart';

class UpdateRepository extends ChangeNotifier {
  UpdateRepository({
    required this.store,
    required this.releases,
    required this.backend,
  });
  final SnapshotStore store;
  final GitHubReleaseClient releases;
  final UpdateBackend backend;
  final _queue = SerialQueue();
  UpdatePreferences _preferences = const UpdatePreferences();
  UpdatePreferences get preferences => _preferences;
  InstalledAppInfo? _installed;
  InstalledAppInfo? get installed => _installed;
  ReleaseCheck? _result;
  ReleaseCheck? get result => _result;
  UpdateTransfer _transfer = const UpdateTransfer();
  UpdateTransfer get transfer => _transfer;
  AppFailure? _error;
  AppFailure? get error => _error;
  bool _checking = false, _operating = false;
  bool get checking => _checking;
  bool get operating => _operating;
  bool _disposed = false, _refreshing = false;
  int _generation = 0, _transferGeneration = 0;
  Timer? _timer;
  final _foregroundOwners = <Object>{};
  String? _promptedInstallId;
  bool get needsInstallPrompt =>
      transfer.ready &&
      transfer.candidateId != null &&
      transfer.candidateId != _promptedInstallId;

  void acknowledgeInstallPrompt() {
    if (transfer.ready) _promptedInstallId = transfer.candidateId;
  }

  void _notify() {
    if (!_disposed) {
      _syncPolling();
      notifyListeners();
    }
  }

  AppFailure _failure(Object e) => e is AppFailure
      ? e
      : AppFailure(
          FailureKind.network,
          e is TimeoutException ? '更新检查超时，请重试' : '无法完成应用更新，请重试',
        );

  Future<void> initialize() async {
    try {
      final prefs = UpdatePreferences.fromJson(await store.read('updates'));
      if (_disposed) return;
      _preferences = prefs;
    } catch (e) {
      if (_disposed) return;
      _preferences = const UpdatePreferences(autoCheck: false);
      _error = _failure(e);
      _notify();
      return;
    }
    try {
      final info = await backend.installedApp();
      if (_disposed) return;
      _installed = info;
      final state = await backend.snapshot();
      if (_disposed) return;
      _transfer = state;
      _error = null;
    } catch (e) {
      if (_disposed) return;
      _error = _failure(e);
    }
    _notify();
  }

  Future<void> _save(UpdatePreferences next) async {
    await store.write('updates', next.toJson());
    if (!_disposed) _preferences = next;
  }

  Future<void> setAutoCheck(bool enabled) => _queue.run(() async {
    if (_disposed) return;
    await _save(_preferences.copyWith(autoCheck: enabled));
    _notify();
  });
  Future<void> setShowUpdatePrompt(bool enabled) => _queue.run(() async {
    if (_disposed) return;
    await _save(_preferences.copyWith(showUpdatePrompt: enabled));
    _notify();
  });
  Future<void> setChannel(UpdateChannel channel) async {
    var changed = false;
    await _queue.run(() async {
      if (_disposed || channel == _preferences.channel) return;
      if (transfer.active) {
        throw const AppFailure(FailureKind.cancelled, '请先取消当前更新下载，再切换渠道');
      }
      await _save(_preferences.copyWith(channel: channel));
      _generation++;
      releases.cancelCheck();
      _checking = false;
      _result = null;
      _error = null;
      changed = true;
      _notify();
    });
    if (changed) await check();
  }

  Future<ReleaseCheck?> check({bool automatic = false}) async {
    final request = await _queue.run(() async {
      if (_disposed || (automatic && (!_preferences.autoCheck || checking))) {
        return null;
      }
      final generation = ++_generation;
      final channel = _preferences.channel;
      releases.cancelCheck();
      _checking = true;
      _error = null;
      _notify();
      return (generation, channel);
    });
    if (request == null || _disposed) return null;
    final (generation, channel) = request;
    try {
      final info = installed ?? await backend.installedApp();
      if (_disposed || generation != _generation) return null;
      _installed = info;
      final next = await releases.check(installed: info, channel: channel);
      if (!_disposed && generation == _generation) {
        _result = next;
        return next;
      }
    } catch (e) {
      if (!_disposed && generation == _generation) {
        _error = _failure(e);
        _result = null;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _checking = false;
        _notify();
      }
    }
    return null;
  }

  Future<void> _operate(Future<void> Function() action) => _queue.run(() async {
    if (_disposed) return;
    _operating = true;
    _transferGeneration++;
    _error = null;
    _notify();
    try {
      await action();
    } catch (e) {
      _error = _failure(e);
      rethrow;
    } finally {
      _operating = false;
      _notify();
    }
  });
  Future<void> download() => _operate(() async {
    final candidate = result?.candidate;
    if (candidate == null) {
      throw const AppFailure(FailureKind.cancelled, '请先检查更新');
    }
    if (transfer.active) {
      throw const AppFailure(FailureKind.cancelled, '已有更新下载，请先完成或取消');
    }
    await backend.enqueue(candidate, candidate.assets.first);
    _promptedInstallId = null;
    _transfer = await backend.snapshot();
  });
  Future<void> cancelDownload() => _operate(() async {
    final id = transfer.candidateId;
    if (id == null) return;
    await backend.cancel(id);
    _transfer = await backend.snapshot();
  });
  Future<void> install() => _operate(() async {
    final id = transfer.candidateId;
    if (id == null || !transfer.ready) {
      throw const AppFailure(FailureKind.cancelled, '请先下载更新');
    }
    _transfer = await backend.requestInstall(id);
  });
  Future<void> refreshTransfer() async {
    if (_disposed || _refreshing || operating) return;
    _refreshing = true;
    final generation = _transferGeneration;
    try {
      final state = await backend.snapshot();
      if (!_disposed && generation == _transferGeneration) {
        _transfer = state;
        _notify();
      }
    } catch (e) {
      if (!_disposed && generation == _transferGeneration) {
        _error = _failure(e);
        _notify();
      }
    } finally {
      _refreshing = false;
    }
  }

  void setForegroundVisible(bool visible, {Object? owner}) {
    if (_disposed) return;
    if (visible) {
      _foregroundOwners.add(owner ?? this);
      unawaited(refreshTransfer());
    } else {
      _foregroundOwners.remove(owner ?? this);
    }
    _syncPolling();
  }

  void _syncPolling() {
    // Only observe native work while the app is visible and a download is pending.
    if (_foregroundOwners.isNotEmpty && transfer.active && !transfer.ready) {
      _timer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refreshTransfer()),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> openPage([Uri? page]) =>
      backend.openReleasePage(page ?? GitHubReleaseClient.releasesPage);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    releases.close();
    super.dispose();
  }
}

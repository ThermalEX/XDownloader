import 'package:flutter/foundation.dart';

import '../../core/models/app_settings.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this.store);
  final SnapshotStore store;
  final _queue = SerialQueue();
  AppSettings _value = const AppSettings();
  AppSettings get value => _value;
  Future<void> initialize() async {
    _value = AppSettings.fromJson(await store.read('settings'));
  }

  Future<void> update(AppSettings next) => edit((_) => next);
  Future<void> edit(AppSettings Function(AppSettings current) transform) =>
      _queue.run(() async {
        final next = transform(_value);
        await store.write('settings', next.toJson());
        _value = next;
        notifyListeners();
      });
}

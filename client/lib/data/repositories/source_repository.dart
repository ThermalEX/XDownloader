import 'package:flutter/foundation.dart';

import '../../core/models/source.dart';
import '../../core/parsing/source_catalog.dart';
import '../../core/parsing/parse_client.dart';
import '../../core/parsing/source_exchange.dart';
import '../../core/models/app_failure.dart';
import '../../platform/download_backend.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

class SourceRepository extends ChangeNotifier {
  SourceRepository(this.store);
  final SnapshotStore store;
  final _queue = SerialQueue();
  List<ParseSource> _custom = [];
  String _currentId = 'xdl';
  bool _autoFallback = true;
  List<ParseSource> get list =>
      List.unmodifiable([...SourceCatalog.builtins, ..._custom]);
  List<ParseSource> get parseOrder => List.unmodifiable([
    ...list.where((s) => s.id == currentId),
    ...list.where((s) => s.id != currentId),
  ]);
  String get currentId => _currentId;
  bool get autoFallback => _autoFallback;
  Future<void> initialize() async {
    final m = await store.read('sources');
    try {
      _custom = (m['custom'] as List? ?? [])
          .map((v) => ParseSource.fromJson(Map<String, dynamic>.from(v as Map)))
          .toList();
      _currentId = m['current'] as String? ?? 'xdl';
      if (!list.any((s) => s.id == _currentId)) _currentId = 'xdl';
      _autoFallback = m['fallback'] != false;
    } on Exception catch (e) {
      throw AppFailure(FailureKind.storage, '解析源配置损坏，原数据已保留', '$e');
    }
  }

  Future<void> _save(
    List<ParseSource> custom,
    String current,
    bool fallback,
  ) async {
    await store.write('sources', {
      'custom': custom.map((s) => s.toJson()).toList(),
      'current': current,
      'fallback': fallback,
    });
    _custom = custom;
    _currentId = current;
    _autoFallback = fallback;
    notifyListeners();
  }

  Future<String> addCustom(ParseSource source) => _queue.run(() async {
    if (!_custom.any((s) => s.id == source.id) &&
        _custom.length >= SourceExchange.maxCustom) {
      throw const AppFailure(FailureKind.malformed, '最多保存 50 个自定义源');
    }
    if (source.name.trim().isEmpty) {
      throw const AppFailure(FailureKind.malformed, '请输入源名称');
    }
    ParseClient.validateSource(source);
    final id = source.id.isEmpty
        ? 'c_${newTaskId().substring(0, 12)}'
        : source.id;
    if (SourceCatalog.builtins.any((s) => s.id == id)) {
      throw const AppFailure(FailureKind.malformed, '不能覆盖内置解析源');
    }
    final next = ParseSource(
      id,
      source.name.trim(),
      source.endpoint.trim(),
      source.kind,
      source.kind == SourceKind.xdl || source.kind == SourceKind.snap
          ? 'POST'
          : source.method.toUpperCase(),
      source.body,
      false,
    );
    await _save(
      [..._custom.where((s) => s.id != id), next],
      _currentId,
      _autoFallback,
    );
    return id;
  });
  Future<void> remove(String id) => _queue.run(() async {
    if (SourceCatalog.builtins.any((s) => s.id == id)) {
      throw const AppFailure(FailureKind.malformed, '内置解析源不能删除');
    }
    await _save(
      _custom.where((s) => s.id != id).toList(),
      _currentId == id ? 'xdl' : _currentId,
      _autoFallback,
    );
  });
  Future<void> select(String id) => _queue.run(() async {
    if (!list.any((s) => s.id == id)) {
      throw const AppFailure(FailureKind.malformed, '解析源不存在');
    }
    await _save(_custom, id, _autoFallback);
  });
  Future<void> setFallback(bool enabled) =>
      _queue.run(() => _save(_custom, _currentId, enabled));

  String exportSources() => SourceExchange.encode(list);
  Future<int> importSources(String text) => _queue.run(() async {
    final imported = SourceExchange.decode(text);
    final identities = list.map(SourceExchange.identity).toSet();
    final next = [..._custom];
    var added = 0;
    for (final source in imported) {
      if (!identities.add(SourceExchange.identity(source))) continue;
      next.add(
        ParseSource(
          'c_${newTaskId().substring(0, 12)}',
          source.name,
          source.endpoint,
          source.kind,
          source.method,
          source.body,
          false,
        ),
      );
      added++;
    }
    if (next.length > SourceExchange.maxCustom) {
      throw const AppFailure(FailureKind.malformed, '最多保存 50 个自定义源，未导入任何条目');
    }
    if (added > 0) await _save(next, _currentId, _autoFallback);
    return added;
  });
}

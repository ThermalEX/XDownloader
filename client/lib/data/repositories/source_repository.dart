import 'package:flutter/foundation.dart';

import '../../core/models/source.dart';
import '../../core/parsing/source_catalog.dart';
import '../../core/parsing/parse_client.dart';
import '../../core/parsing/source_exchange.dart';
import '../../core/models/app_failure.dart';
import '../../core/models/media.dart';
import '../../platform/download_backend.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

class SourceRepository extends ChangeNotifier {
  SourceRepository(this.store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  List<String> _order = [];
  final _failedUntil = <String, DateTime>{};
  bool _disposed = false;
  final SnapshotStore store;
  final _queue = SerialQueue();
  List<ParseSource> _custom = [];
  String _currentId = 'xdl';
  bool _autoFallback = true;
  List<ParseSource> get list {
    final remaining = {
      for (final s in [...SourceCatalog.builtins, ..._custom]) s.id: s,
    };
    final sorted = <ParseSource>[];
    for (final id in _order) {
      final source = remaining.remove(id);
      if (source != null) sorted.add(source);
    }
    return List.unmodifiable([...sorted, ...remaining.values]);
  }

  List<ParseSource> get parseOrder {
    final ordered = list;
    final now = _now();
    return List.unmodifiable([
      ...ordered.where((s) => s.id == currentId),
      ...ordered.where(
        (s) =>
            s.id != currentId && !(_failedUntil[s.id]?.isAfter(now) ?? false),
      ),
    ]);
  }

  void recordAttempt(String id, bool success) {
    if (_disposed || !list.any((s) => s.id == id)) return;
    if (success) {
      _failedUntil.remove(id);
    } else {
      _failedUntil[id] = _now().add(const Duration(minutes: 2));
    }
  }

  Future<MediaResult> runParse(
    ParseClient parser,
    String input,
    ParseCancellation cancellation,
  ) async {
    final result = await parser.parse(
      input,
      sources: parseOrder,
      autoFallback: autoFallback,
      cancellation: cancellation,
    );
    if (!cancellation.isCancelled) recordAttempt(result.sourceId, true);
    return result;
  }

  Future<void> movePriority(String id, int direction) => _queue.run(() async {
    if (direction != -1 && direction != 1) {
      throw const AppFailure(FailureKind.malformed, '优先级调整无效');
    }
    final ids = list.map((s) => s.id).toList();
    final index = ids.indexOf(id);
    if (index < 0) throw const AppFailure(FailureKind.malformed, '解析源不存在');
    final target = index + direction;
    if (target < 0 || target >= ids.length) return;
    ids.removeAt(index);
    ids.insert(target, id);
    await _save(_custom, _currentId, _autoFallback, order: ids);
  });
  String get currentId => _currentId;
  bool get autoFallback => _autoFallback;
  Future<void> initialize() async {
    final m = await store.read('sources');
    try {
      _order = (m['order'] as List? ?? []).cast<String>();
      if (_order.toSet().length != _order.length) {
        throw const FormatException('Duplicate source order');
      }
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
    bool fallback, {
    List<String>? order,
  }) async {
    await store.write('sources', {
      'custom': custom.map((s) => s.toJson()).toList(),
      'current': current,
      'fallback': fallback,
      'order': order ?? _order,
    });
    _order = order ?? _order;
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
      source.requestMethod,
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
    _failedUntil.remove(id);
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
    _failedUntil.remove(id);
  });
  Future<void> setFallback(bool enabled) =>
      _queue.run(() => _save(_custom, _currentId, enabled));

  String exportSources({Set<String>? ids}) {
    if (ids != null &&
        (ids.isEmpty || ids.any((id) => !list.any((s) => s.id == id)))) {
      throw const AppFailure(FailureKind.malformed, '请选择存在的解析源');
    }
    return SourceExchange.encode(
      list.where((s) => ids == null || ids.contains(s.id)).toList(),
    );
  }

  Future<int> importSources(
    String text, {
    Set<int>? selectedIndices,
  }) => _queue.run(() async {
    final decoded = SourceExchange.decode(text);
    if (selectedIndices != null &&
        (selectedIndices.isEmpty ||
            selectedIndices.any((i) => i < 0 || i >= decoded.length))) {
      throw const AppFailure(FailureKind.malformed, '请选择要导入的解析源');
    }
    final imported = [
      for (var i = 0; i < decoded.length; i++)
        if (selectedIndices == null || selectedIndices.contains(i)) decoded[i],
    ];
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
  @override
  void dispose() {
    _disposed = true;
    _failedUntil.clear();
    super.dispose();
  }
}

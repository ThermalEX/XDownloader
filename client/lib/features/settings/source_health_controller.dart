import 'package:flutter/foundation.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/media.dart';
import '../../core/models/source.dart';
import '../../core/parsing/parse_client.dart';

class SourceHealthController extends ChangeNotifier {
  SourceHealthController(this.parser);
  final ParseClient parser;
  final _pending = <String, ParseCancellation>{};
  final _results = <String, String>{};
  bool _disposed = false;
  bool _checkingAll = false;
  bool get checkingAll => _checkingAll;
  bool checking(String id) => _pending.containsKey(id);
  String? result(String id) => _results[id];

  Future<void> check(ParseSource source) async {
    if (_disposed || checking(source.id)) return;
    final cancellation = ParseCancellation();
    _pending[source.id] = cancellation;
    _results.remove(source.id);
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final media = await parser.parse(
        'https://x.com/9GAG/status/1661175429859012608',
        sources: [source],
        autoFallback: false,
        cancellation: cancellation,
      );
      final variants = media.items.expand((item) => item.variants).toList()
        ..sort(compareVariants);
      if (variants.isEmpty) {
        throw const AppFailure(FailureKind.noVideo, '未解析到视频');
      }
      final best = variants.first;
      final size = best.width > 0 && best.height > 0
          ? '${best.width} × ${best.height}'
          : best.extension.toUpperCase();
      _results[source.id] =
          '可用 · $size · ${media.items.length} 个视频 / ${variants.length} 档 · ${watch.elapsedMilliseconds} ms';
    } catch (error) {
      _results[source.id] =
          '不可用 · ${error is AppFailure ? error.message : '检测失败，请重试'}';
    } finally {
      _pending.remove(source.id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> checkAll(List<ParseSource> sources) async {
    if (_disposed || _checkingAll) return;
    _checkingAll = true;
    notifyListeners();
    var next = 0;
    Future<void> worker() async {
      while (!_disposed && next < sources.length) {
        await check(sources[next++]);
      }
    }

    try {
      await Future.wait(List.generate(3, (_) => worker()));
    } finally {
      _checkingAll = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final cancellation in _pending.values) {
      cancellation.cancel();
    }
    super.dispose();
  }
}

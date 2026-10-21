import 'dart:convert';
import 'dart:io';

import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/source_catalog.dart';

/// Live availability is separate from deterministic fixture tests.
Future<void> main(List<String> args) async {
  final input = args.isEmpty
      ? 'https://x.com/9GAG/status/1661175429859012608'
      : args.first;
  final checks = SourceCatalog.builtins.map((source) async {
    final watch = Stopwatch()..start();
    try {
      final result = await ParseClient().parse(
        input,
        sources: [source],
        autoFallback: false,
        cancellation: ParseCancellation(),
      );
      stdout.writeln(
        jsonEncode({
          'source': source.id,
          'ok': true,
          'ms': watch.elapsedMilliseconds,
          'media': result.items.length,
          'variants': result.items.fold<int>(
            0,
            (n, m) => n + m.variants.length,
          ),
        }),
      );
      return true;
    } catch (e) {
      stdout.writeln(
        jsonEncode({
          'source': source.id,
          'ok': false,
          'ms': watch.elapsedMilliseconds,
          'error': '$e',
        }),
      );
      return false;
    }
  });
  if ((await Future.wait(checks)).contains(false)) exitCode = 1;
}

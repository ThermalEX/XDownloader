import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/platform/share_gateway.dart';

void main() {
  test('cold share is consumed once and hot events remain separate', () async {
    var reads = 0;
    final events = StreamController<Object?>.broadcast();
    final gateway = ShareGateway(
      call: (_, _) async {
        reads++;
        return ' cold ';
      },
      events: events.stream,
    );
    expect(await gateway.initialText(), 'cold');
    expect(await gateway.initialText(), isNull);
    expect(reads, 1);
    final received = <String>[];
    final subscription = gateway.sharedText.listen(received.add);
    events.add('hot');
    events.add(null);
    events.add('  ');
    events.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(received, ['hot']);
    await subscription.cancel();
    await events.close();
  });
  test('null and empty initial text are harmless', () async {
    for (final value in [null, '', '  ']) {
      final gateway = ShareGateway(
        call: (_, _) async => value,
        events: const Stream.empty(),
      );
      expect(await gateway.initialText(), isNull);
    }
  });
}

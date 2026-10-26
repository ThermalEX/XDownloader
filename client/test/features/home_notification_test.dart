import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/features/home/home_controller.dart';

import '../support/app_fixture.dart';

void main() {
  late AppFixture fixture;
  late HomeController controller;

  setUp(() async {
    fixture = AppFixture();
    await fixture.initialize();
    controller = HomeController(fixture.dependencies);
  });
  tearDown(() async {
    controller.dispose();
    await fixture.close();
  });

  for (final action in ['setInput', 'clear']) {
    test(
      '$action publishes only the final state and cancels stale parsing',
      () async {
        final gate = Completer<MediaResult>();
        late ParseCancellation cancellation;
        fixture.parser.respond = (_, token) {
          cancellation = token;
          return gate.future;
        };
        final pending = controller.parse('https://x.com/a/status/123456');
        final observed = <(String, bool, MediaResult?, Object?)>[];
        controller.addListener(() {
          observed.add((
            controller.input,
            controller.busy,
            controller.result,
            controller.error,
          ));
        });

        if (action == 'setInput') {
          controller.setInput('new input');
        } else {
          controller.clear();
        }

        expect(observed, [
          (action == 'setInput' ? 'new input' : '', false, null, null),
        ]);
        expect(cancellation.isCancelled, isTrue);
        gate.complete(resultFor('123456'));
        await pending;
        expect(controller.result, isNull);
        expect(observed, hasLength(1));
      },
    );
  }

  test('standalone cancellation still notifies observers', () async {
    final gate = Completer<MediaResult>();
    fixture.parser.respond = (_, _) => gate.future;
    final pending = controller.parse('https://x.com/a/status/123456');
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.cancelParse();
    expect(controller.busy, isFalse);
    expect(notifications, 1);
    gate.complete(resultFor('123456'));
    await pending;
    expect(controller.result, isNull);
    expect(notifications, 1);
  });
}

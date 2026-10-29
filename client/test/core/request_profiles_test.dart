import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/request_rotation.dart';
import 'package:xdownloader/core/parsing/request_profiles.dart';

void main() {
  late DateTime now;
  late RequestProfiles profiles;
  setUp(() {
    now = DateTime.utc(2026, 10, 28, 12);
    profiles = RequestProfiles(now: () => now, random: Random(9));
  });

  test('disabled sources add no headers and counts are isolated by source', () {
    expect(profiles.begin('off').headers, isEmpty);
    profiles.configure({
      'a': const RequestRotation(RotationMode.count, 2),
      'b': const RequestRotation(RotationMode.count, 2),
    });
    final a = profiles.begin('a'), b = profiles.begin('b');
    profiles.complete(a);
    expect(profiles.begin('a').headers, a.headers);
    profiles.complete(profiles.begin('a'));
    expect(profiles.begin('a').headers, isNot(a.headers));
    expect(profiles.begin('b').headers, b.headers);
  });

  test(
    'time threshold rotates only the next attempt and captures are immutable',
    () {
      profiles.configure({'a': const RequestRotation(RotationMode.minutes, 5)});
      final a = profiles.begin('a');
      now = now.add(const Duration(minutes: 4, seconds: 59));
      expect(profiles.begin('a').headers, a.headers);
      now = now.add(const Duration(seconds: 1));
      final next = profiles.begin('a');
      expect(next.headers, isNot(a.headers));
      expect(
        next.headers['accept-language'],
        isNot(a.headers['accept-language']),
      );
      expect(() => a.headers['user-agent'] = 'changed', throwsUnsupportedError);
      profiles.complete(
        a,
      ); // A late completion belongs to its captured session.
      expect(profiles.begin('a').headers, next.headers);
    },
  );

  test(
    'editing one policy invalidates its session but preserves other sessions',
    () {
      const one = RequestRotation(RotationMode.count, 1);
      profiles.configure({'a': one, 'b': one});
      final a = profiles.begin('a'), b = profiles.begin('b');
      profiles.configure({
        'a': const RequestRotation(RotationMode.count, 2),
        'b': one,
      });
      final fresh = profiles.begin('a');
      profiles.complete(a);
      expect(profiles.begin('a').headers, fresh.headers);
      expect(profiles.begin('b').headers, b.headers);
      profiles.configure({});
      expect(profiles.begin('a').headers, isEmpty);
    },
  );

  test(
    '429 cooldown survives policy edits and only expires at the deadline',
    () {
      profiles.recordResponse('a', 429, {'retry-after': '300'});
      profiles.configure({'a': const RequestRotation(RotationMode.count, 1)});
      expect(profiles.cooldownRemaining('a'), const Duration(minutes: 5));
      expect(profiles.cooldownRemaining('b'), Duration.zero);
      now = now.add(const Duration(minutes: 5));
      expect(profiles.cooldownRemaining('a'), Duration.zero);
    },
  );

  test(
    'Retry-After supports HTTP dates, defaults safely and caps huge delays',
    () {
      profiles.recordResponse('date', 503, {
        'retry-after': 'Wed, 28 Oct 2026 12:03:00 GMT',
      });
      expect(profiles.cooldownRemaining('date'), const Duration(minutes: 3));
      for (final value in [
        null,
        'invalid',
        '-1',
        '0',
        'Tue, 27 Oct 2026 12:00:00 GMT',
      ]) {
        profiles.recordResponse('a', 429, {'retry-after': ?value});
        expect(profiles.cooldownRemaining('a'), const Duration(minutes: 2));
      }
      profiles.recordResponse('huge', 429, {
        'retry-after': '999999999999999999999999',
      });
      expect(profiles.cooldownRemaining('huge'), const Duration(hours: 24));
      profiles.recordResponse('normal', 503, {});
      expect(profiles.cooldownRemaining('normal'), Duration.zero);
      profiles.recordResponse('normal', 403, {'retry-after': '60'});
      expect(profiles.cooldownRemaining('normal'), Duration.zero);
    },
  );

  test('invalid persisted policies reject malformed values instead of enabling rotation', () {
    for (final json in [
      {'mode': 'unexpected', 'interval': 1},
      {'mode': 'minutes', 'interval': 0},
      {'mode': 'minutes', 'interval': 1441},
      {'mode': 'count', 'interval': 1001},
      {'mode': 'count', 'interval': 1.5},
    ]) {
      expect(() => RequestRotation.fromJson(json), throwsFormatException);
    }
  });
}

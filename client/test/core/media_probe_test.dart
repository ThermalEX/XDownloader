import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';

import '../support/fixture_client.dart';

void main() {
  test(
    'cancelling a hung media body cancels its stream subscription',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final parser = ParseClient(
        clientFactory: () => _StreamClient(body.stream),
      );
      final token = ParseCancellation();
      final pending = parser.verifyMedia(
        Uri.parse('https://video.test/a.mp4'),
        token,
      );
      final failed = expectLater(
        pending,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await failed;
      expect(cancelled, isTrue);
      await body.close();
    },
  );

  test(
    'media probe uses GET Range and rejects HTML despite successful HTTP',
    () async {
      final parser = ParseClient(
        clientFactory: () => FixtureClient((r) {
          expect(r.method, 'GET');
          expect(r.headers['range'], 'bytes=0-31');
          return http.Response('<html>oops</html>', 200);
        }),
      );
      await expectLater(
        parser.verifyMedia(
          Uri.parse('https://video.test/a.mp4'),
          ParseCancellation(),
        ),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test(
    'media probe accepts MP4 signature and pre-cancel avoids requests',
    () async {
      var calls = 0;
      final parser = ParseClient(
        clientFactory: () => FixtureClient((r) {
          calls++;
          return http.Response.bytes([
            0,
            0,
            0,
            32,
            102,
            116,
            121,
            112,
            1,
            2,
          ], 206);
        }),
      );
      await parser.verifyMedia(
        Uri.parse('https://video.test/a.mp4'),
        ParseCancellation(),
      );
      expect(calls, 1);
      final cancel = ParseCancellation()..cancel();
      await expectLater(
        parser.verifyMedia(Uri.parse('https://video.test/a.mp4'), cancel),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.cancelled,
          ),
        ),
      );
      expect(calls, 1);
    },
  );
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.body);
  final Stream<List<int>> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(body, 206);
}

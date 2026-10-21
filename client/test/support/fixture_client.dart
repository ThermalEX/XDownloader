import 'dart:async';

import 'package:http/http.dart' as http;

/// The HTTP socket boundary only; parser, deadlines and cancellation run normally.
class FixtureClient extends http.BaseClient {
  FixtureClient(this.respond);
  final FutureOr<http.Response> Function(http.Request) respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await respond(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() {
    closed = true;
  }
}

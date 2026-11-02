import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xdownloader/data/backup/webdav_client.dart';

WebDavConfig config({String folder = 'XDownloader'}) => WebDavConfig(
  endpoint: Uri.parse('https://dav.example/base/'),
  username: 'alice',
  folder: folder,
);

String response(String href, {String props = '', String status = '200 OK'}) =>
    '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
    '$props</d:prop><d:status>HTTP/1.1 $status</d:status>'
    '</d:propstat></d:response>';

String listing(List<String> entries) =>
    '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
    '${entries.join()}</d:multistatus>';

WebDavEntry entry([String name = 'old.zip']) => WebDavEntry(
  uri: Uri.parse('https://dav.example/base/XDownloader/$name'),
  name: name,
);

void main() {
  test('config roundtrips without passwords and encodes folder components', () {
    final original = config(folder: '中文/backup files');
    final restored = WebDavConfig.fromJson(original.toJson());
    expect(restored.endpoint, original.endpoint);
    expect(restored.folder, original.folder);
    expect(restored.username, 'alice');
    expect(restored.toJson().containsKey('password'), isFalse);
    expect(
      () => WebDavConfig(
        endpoint: Uri.parse('http://dav.example/'),
        username: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => WebDavConfig(
        endpoint: Uri.parse('https://user:pass@dav.example/'),
        username: '',
      ),
      throwsArgumentError,
    );
    expect(() => config(folder: '../other'), throwsArgumentError);
    expect(() => config(folder: '%2e%2e/other'), throwsArgumentError);
    expect(
      () => WebDavConfig(
        endpoint: Uri.parse('https://dav.example/base/?secret=1'),
        username: '',
      ),
      throwsArgumentError,
    );
    expect(
      () => WebDavConfig(
        // Uri.parse already normalizes a single encoded dot segment away.
        endpoint: Uri.parse('https://dav.example/%252e%252e/'),
        username: '',
      ),
      throwsArgumentError,
    );
  });

  test(
    'parses successful DAV propstat only and filters untrusted hrefs',
    () async {
      final transport = WebDavClient(
        config: config(),
        password: 'secret',
        client: MockClient((request) async {
          expect(request.method, 'PROPFIND');
          expect(request.headers['Depth'], '1');
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['Authorization'],
            'Basic ${base64Encode(utf8.encode('alice:secret'))}',
          );
          return http.Response(
            listing([
              response(
                '/base/XDownloader/',
                props: '<d:resourcetype><d:collection/></d:resourcetype>',
              ),
              response(
                'one.zip',
                props: '<d:getetag>"first"</d:getetag><d:getcontentlength>12</d:getcontentlength><d:getlastmodified>Sun, 01 Nov 2026 12:00:00 GMT</d:getlastmodified>',
              ),
              '<d:response><d:href>/base/XDownloader/two.zip</d:href>'
                  '<d:propstat><d:prop><d:getetag>wrong</d:getetag></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>'
                  '<d:propstat><d:prop><d:getcontentlength>4</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
              response('https://evil.example/base/XDownloader/stolen.zip'),
              response('/base/outside.zip'),
              response('%2e%2e/escaped.zip'),
              response('nested/hidden.zip'),
              response('notes.txt'),
              response('bad.zip', status: '403 Forbidden'),
            ]),
            207,
          );
        }),
      );
      final entries = await transport.list();
      expect(entries.map((item) => item.name), ['one.zip', 'two.zip']);
      expect(entries.first.bytes, 12);
      expect(entries.first.etag, '"first"');
      expect(entries.first.modifiedAt, DateTime.utc(2026, 11, 1, 12));
      expect(entries.last.etag, isNull);
      expect(entries.first.fingerprint, isNot(entries.last.fingerprint));
    },
  );

  test(
    'rejects redirects without issuing a second authenticated request',
    () async {
      var calls = 0;
      final transport = WebDavClient(
        config: config(),
        password: 'secret',
        client: MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://evil.example/'},
          );
        }),
      );
      await expectLater(transport.read(entry()), throwsA(isA<Exception>()));
      expect(calls, 1);
    },
  );

  test(
    'rejects caller supplied entries outside the configured folder',
    () async {
      var calls = 0;
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        transport.read(
          WebDavEntry(
            uri: Uri.parse('https://evil.example/a.zip'),
            name: 'a.zip',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        transport.delete(
          WebDavEntry(
            uri: Uri.parse(
              'https://dav.example/base/XDownloader/%252e%252e/a.zip',
            ),
            name: 'a.zip',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(calls, 0);
    },
  );

  test('read rejects partial, oversized and truncated bodies', () async {
    for (final result in [
      http.Response('partial', 206),
      http.Response(
        'small',
        200,
        headers: {'content-length': '${16 * 1024 * 1024 + 1}'},
      ),
      http.Response('small', 200, headers: {'content-length': '100'}),
    ]) {
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((_) async => result),
      );
      await expectLater(transport.read(entry()), throwsA(isA<Exception>()));
    }
  });

  test(
    'streaming limits reject actual bytes even without length headers',
    () async {
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: _StreamClient(
          (_) async => http.StreamedResponse(
            Stream.value(List<int>.filled(16 * 1024 * 1024 + 1, 1)),
            200,
          ),
        ),
      );
      await expectLater(transport.read(entry()), throwsA(isA<Exception>()));
    },
  );

  test(
    'listing rejects excess entries, excess XML and external entities',
    () async {
      for (final body in [
        listing(List.generate(1001, (i) => response('$i.zip'))),
        ' ' * (8 * 1024 * 1024 + 1),
        '<!DOCTYPE x [<!ENTITY leak SYSTEM "file:///secret">]><d:multistatus xmlns:d="DAV:"/>',
      ]) {
        final transport = WebDavClient(
          config: config(),
          password: '',
          client: MockClient((_) async => http.Response(body, 207)),
        );
        await expectLater(transport.list(), throwsA(isA<Exception>()));
      }
    },
  );

  test(
    'cancellation before and during response prevents returning data',
    () async {
      var cancelled = true;
      var calls = 0;
      final transport = WebDavClient(
        config: config(),
        password: '',
        isCancelled: () => cancelled,
        client: MockClient((_) async {
          calls++;
          cancelled = true;
          return http.Response('archive', 200);
        }),
      );
      await expectLater(transport.read(entry()), throwsA(isA<Exception>()));
      expect(calls, 0);
      cancelled = false;
      await expectLater(transport.read(entry()), throwsA(isA<Exception>()));
      expect(calls, 1);
    },
  );

  test('creates nested folders and verifies upload bytes with a GET', () async {
    final requests = <http.Request>[];
    final payload = utf8.encode('archive bytes');
    final transport = WebDavClient(
      config: config(folder: '中文/nested'),
      password: '',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'MKCOL') return http.Response('', 201);
        if (request.method == 'PUT') {
          expect(request.headers['If-None-Match'], '*');
          expect(request.bodyBytes, payload);
          return http.Response('', 201);
        }
        return http.Response.bytes(
          payload,
          200,
          headers: {'etag': '"uploaded"'},
        );
      }),
    );
    final uploaded = await transport.upload('unique.zip', payload);
    expect(requests.map((r) => r.method), ['MKCOL', 'MKCOL', 'PUT', 'GET']);
    expect(requests.first.url.pathSegments, ['base', '中文', '']);
    expect(uploaded.name, 'unique.zip');
    expect(uploaded.etag, '"uploaded"');
  });

  test(
    'conditional upload refuses 412 without overwriting or deleting',
    () async {
      final methods = <String>[];
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((r) async {
          methods.add(r.method);
          return http.Response('', r.method == 'MKCOL' ? 201 : 412);
        }),
      );
      await expectLater(
        transport.upload('old.zip', [1]),
        throwsA(isA<Exception>()),
      );
      expect(methods, ['MKCOL', 'PUT']);
    },
  );

  test(
    'uncertain upload succeeds only when recovery GET matches hash',
    () async {
      for (final matches in [true, false]) {
        final methods = <String>[];
        final transport = WebDavClient(
          config: config(),
          password: '',
          client: MockClient((r) async {
            methods.add(r.method);
            if (r.method == 'MKCOL') return http.Response('', 201);
            if (r.method == 'PUT') {
              throw http.ClientException('connection dropped');
            }
            return http.Response.bytes(matches ? [1, 2, 3] : [3, 2, 1], 200);
          }),
        );
        if (matches) {
          expect((await transport.upload('same.zip', [1, 2, 3])).bytes, 3);
        } else {
          await expectLater(
            transport.upload('same.zip', [1, 2, 3]),
            throwsA(isA<Exception>()),
          );
        }
        expect(methods, ['MKCOL', 'PUT', 'GET']);
      }
    },
  );

  test('connection test cleans only its newly created random probe', () async {
    final paths = <String>[];
    List<int>? bytes;
    final transport = WebDavClient(
      config: config(),
      password: '',
      client: MockClient((r) async {
        if (r.method == 'MKCOL') return http.Response('', 201);
        paths.add(r.url.path);
        if (r.method == 'PUT') {
          bytes = r.bodyBytes;
          expect(r.headers['If-None-Match'], '*');
          return http.Response('', 201);
        }
        if (r.method == 'GET') return http.Response.bytes(bytes!, 200);
        expect(r.method, 'DELETE');
        return http.Response('', 204);
      }),
    );
    await transport.testConnection();
    expect(paths.length, 3);
    expect(paths.toSet().length, 1);
    expect(paths.first, contains('.xdl-connection-'));
    expect(paths.first, isNot(contains('.zip')));
  });

  test(
    'connection probe conflict never deletes an existing remote file',
    () async {
      final methods = <String>[];
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((r) async {
          methods.add(r.method);
          return http.Response('', r.method == 'MKCOL' ? 201 : 412);
        }),
      );
      await expectLater(transport.testConnection(), throwsA(isA<Exception>()));
      expect(methods, ['MKCOL', 'PUT']);
    },
  );

  test(
    'connection verification failure cleans its confirmed new probe',
    () async {
      final methods = <String>[];
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((r) async {
          methods.add(r.method);
          if (r.method == 'MKCOL' || r.method == 'PUT') {
            return http.Response('', 201);
          }
          if (r.method == 'GET') return http.Response('wrong bytes', 200);
          return http.Response('', 204);
        }),
      );
      await expectLater(transport.testConnection(), throwsA(isA<Exception>()));
      expect(methods, ['MKCOL', 'PUT', 'GET', 'DELETE']);
    },
  );

  test(
    'cancellation during a stalled send returns and aborts the request',
    () async {
      var cancelled = false;
      final started = Completer<void>();
      final aborted = Completer<void>();
      final transport = WebDavClient(
        config: config(),
        password: '',
        isCancelled: () => cancelled,
        client: _StreamClient((r) async {
          started.complete();
          await (r as http.Abortable).abortTrigger;
          aborted.complete();
          throw http.RequestAbortedException();
        }),
      );
      final read = transport.read(entry());
      await started.future;
      cancelled = true;
      await expectLater(read, throwsA(isA<Exception>()));
      await aborted.future;
    },
  );

  test('existing folder must be a DAV collection before upload', () async {
    final methods = <String>[];
    final transport = WebDavClient(
      config: config(),
      password: '',
      client: MockClient((r) async {
        methods.add(r.method);
        if (r.method == 'MKCOL') return http.Response('', 405);
        if (r.method == 'PROPFIND') {
          return http.Response(
            listing([
              response('/base/XDownloader/', props: '<d:resourcetype/>'),
            ]),
            207,
          );
        }
        return http.Response('', 500);
      }),
    );
    await expectLater(
      transport.upload('new.zip', [1]),
      throwsA(isA<Exception>()),
    );
    expect(methods, ['MKCOL', 'PROPFIND']);
  });

  test(
    'accepts an existing verified collection and cleans a probe after retry',
    () async {
      var deletes = 0;
      List<int>? uploaded;
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((r) async {
          if (r.method == 'MKCOL') return http.Response('', 405);
          if (r.method == 'PROPFIND') {
            expect(r.headers['Depth'], '0');
            return http.Response(
              listing([
                response(
                  '/base/XDownloader/',
                  props: '<d:resourcetype><d:collection/></d:resourcetype>',
                ),
              ]),
              207,
            );
          }
          if (r.method == 'PUT') {
            uploaded = r.bodyBytes;
            return http.Response('', 201);
          }
          if (r.method == 'GET') return http.Response.bytes(uploaded!, 200);
          if (++deletes == 1) {
            throw http.ClientException('temporary cleanup failure');
          }
          return http.Response('', 204);
        }),
      );
      await transport.testConnection();
      expect(deletes, 2);
    },
  );
  test(
    'requests identity encoding and rejects partial content marked as 200',
    () async {
      String? encoding;
      final transport = WebDavClient(
        config: config(),
        password: '',
        client: MockClient((r) async {
          encoding = r.headers['Accept-Encoding'];
          return http.Response(
            'fragment',
            200,
            headers: {'content-range': 'bytes 0-7/100'},
          );
        }),
      );
      await expectLater(transport.read(entry()), throwsA(isA<Exception>()));
      expect(encoding, 'identity');
    },
  );
  test('explicit retry reconciles an accepted upload after failed verification GET', () async {
    final methods = <String>[];
    final payload = [1, 2, 3];
    List<int>? remote;
    var reads = 0;
    final transport = WebDavClient(
      config: config(),
      password: '',
      client: MockClient((request) async {
        methods.add(request.method);
        if (request.method == 'MKCOL') return http.Response('', 201);
        if (request.method == 'PUT') {
          expect(request.headers['If-None-Match'], '*');
          if (remote != null) return http.Response('', 412);
          remote = List<int>.from(request.bodyBytes);
          return http.Response('', 201);
        }
        expect(request.method, 'GET');
        if (reads++ == 0) {
          throw http.ClientException('verification connection dropped');
        }
        return http.Response.bytes(remote!, 200, headers: {'etag': '"same"'});
      }),
    );
    await expectLater(
      transport.upload('retry.zip', payload),
      throwsA(isA<WebDavException>()),
    );
    final result = await transport.upload(
      'retry.zip',
      payload,
      reconcileExisting: true,
    );
    expect(result.bytes, payload.length);
    expect(result.etag, '"same"');
    expect(remote, payload);
    expect(methods, ['MKCOL', 'PUT', 'GET', 'MKCOL', 'PUT', 'GET']);
  });

  test('explicit retry rejects different existing bytes without overwrite or delete', () async {
    final methods = <String>[];
    final remote = [9, 8, 7];
    final transport = WebDavClient(
      config: config(),
      password: '',
      client: MockClient((request) async {
        methods.add(request.method);
        if (request.method == 'MKCOL') return http.Response('', 201);
        if (request.method == 'PUT') {
          expect(request.headers['If-None-Match'], '*');
          return http.Response('', 412);
        }
        expect(request.method, 'GET');
        return http.Response.bytes(remote, 200);
      }),
    );
    await expectLater(
      transport.upload('existing.zip', [1, 2, 3], reconcileExisting: true),
      throwsA(isA<WebDavException>()),
    );
    expect(remote, [9, 8, 7]);
    expect(methods, ['MKCOL', 'PUT', 'GET']);
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

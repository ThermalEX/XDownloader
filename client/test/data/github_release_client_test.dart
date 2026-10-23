import 'dart:convert';
import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/data/updates/github_release_client.dart';

Map<String, Object?> manifest(int code, {bool beta = false}) => {
  'schema': 1,
  'versionName': beta ? '2.6.0-beta.1' : '2.5.0',
  'versionCode': code,
  'channel': beta ? 'beta' : 'stable',
  'packageName': 'com.xdl.app',
  'minSdk': 26,
  'assets': [
    {
      'name': 'app-arm.apk',
      'abis': ['arm64-v8a'],
      'bytes': 80,
      'sha256': 'a' * 64,
    },
    {
      'name': 'app.apk',
      'abis': ['armeabi-v7a', 'arm64-v8a', 'x86_64'],
      'bytes': 100,
      'sha256': 'b' * 64,
    },
  ],
};
Map<String, Object?> release(int code, {bool beta = false}) => {
  'id': code,
  'tag_name': beta ? 'v2.6.0-beta.1' : 'v2.5.0',
  'draft': false,
  'prerelease': beta,
  'body': 'Release $code',
  'html_url':
      'https://github.com/ThermalEX/XDownloader/releases/tag/${beta ? 'v2.6.0-beta.1' : 'v2.5.0'}',
  'assets': [
    for (final name in ['update.json', 'app-arm.apk', 'app.apk'])
      {
        'name': name,
        'state': 'uploaded',
        'size': name == 'app-arm.apk' ? 80 : 100,
        'browser_download_url':
            'https://github.com/ThermalEX/XDownloader/releases/download/${beta ? 'v2.6.0-beta.1' : 'v2.5.0'}/$name',
      },
  ],
};
InstalledAppInfo installed({
  int code = 14,
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a'],
}) => InstalledAppInfo(
  packageName: 'com.xdl.app',
  versionName: '2.4.1',
  versionCode: code,
  sdkInt: 37,
  supportedAbis: abis,
);

void main() {
  test(
    'a fatal manifest timeout aborts without waiting for other manifests',
    () async {
      final gates = List.generate(3, (_) => Completer<http.Response>());
      final started = Completer<void>();
      var count = 0;
      final client = GitHubReleaseClient(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(
              jsonEncode([release(16), release(17), release(18)]),
              200,
            );
          }
          final gate = gates[count++];
          if (count == 3) started.complete();
          return gate.future;
        }),
      );
      try {
        final checking = client.check(
          installed: installed(),
          channel: UpdateChannel.stable,
        );
        await started.future.timeout(const Duration(seconds: 2));
        final failure = TimeoutException('one manifest timed out');
        gates.first.completeError(failure);
        await expectLater(
          checking.timeout(const Duration(seconds: 2)),
          throwsA(same(failure)),
        );
      } finally {
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete(http.Response('{}', 200));
        }
        client.close();
      }
    },
  );
  test('manifest checks overlap with at most three requests and retain the highest code', () async {
    final gates = List.generate(7, (_) => Completer<http.Response>());
    final started = <int>[];
    final first = Completer<void>();
    var active = 0, peak = 0;
    final entries = [
      for (var i = 0; i < gates.length; i++)
        {
          ...release(16 + i),
          'tag_name': 'v2.5.$i',
          'html_url':
              'https://github.com/ThermalEX/XDownloader/releases/tag/v2.5.$i',
          'assets': [
            for (final name in ['update.json', 'app-arm.apk', 'app.apk'])
              {
                'name': name,
                'state': 'uploaded',
                'size': name == 'app-arm.apk' ? 80 : 100,
                'browser_download_url':
                    'https://github.com/ThermalEX/XDownloader/releases/download/v2.5.$i/$name',
              },
          ],
        },
    ];
    final client = GitHubReleaseClient(
      client: MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(jsonEncode(entries), 200);
        }
        final i = int.parse(request.url.pathSegments[4].split('.').last);
        started.add(i);
        if (!first.isCompleted) first.complete();
        active++;
        if (active > peak) peak = active;
        try {
          return await gates[i].future;
        } finally {
          active--;
        }
      }),
    );
    try {
      final checking = client.check(
        installed: installed(),
        channel: UpdateChannel.stable,
      );
      await first.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(started.length, 3);
      for (var i = gates.length - 1; i >= 0; i--) {
        gates[i].complete(
          http.Response(
            jsonEncode({...manifest(16 + i), 'versionName': '2.5.$i'}),
            200,
          ),
        );
      }
      final result = await checking;
      expect(peak, 3);
      expect(result.candidate!.versionCode, 22);
      expect(result.validReleases, 7);
      expect(result.scopeComplete, isTrue);
    } finally {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete(http.Response('{}', 200));
      }
      client.close();
    }
  });
  Future<ReleaseCheck> check(
    List<Map<String, Object?>> releases, {
    UpdateChannel channel = UpdateChannel.stable,
    int current = 14,
    List<String> abis = const ['arm64-v8a'],
    Object? Function(Uri)? response,
  }) async {
    final client = GitHubReleaseClient(
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode(releases),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final custom = response?.call(request.url);
        return http.Response(
          jsonEncode(
            custom ??
                manifest(
                  request.url.path.contains('beta') ? 17 : 16,
                  beta: request.url.path.contains('beta'),
                ),
          ),
          200,
        );
      }),
    );
    try {
      return await client.check(
        installed: installed(code: current, abis: abis),
        channel: channel,
      );
    } finally {
      client.close();
    }
  }

  test(
    'release title comes from GitHub name, independent of description',
    () async {
      final candidate = (await check([
        {
          ...release(16),
          'name': '  XDownloader 发布标题  ',
          'body': '## 正文说明\n\n- 修复下载',
        },
      ])).candidate!;
      expect(candidate.title, 'XDownloader 发布标题');
      expect(candidate.notes, '## 正文说明\n\n- 修复下载');
      for (final name in [null, '', '   ', 123]) {
        final fallback = (await check([
          {...release(16), 'name': name},
        ])).candidate!;
        expect(fallback.displayTitle, 'XDownloader 2.5.0');
      }
    },
  );
  test(
    'stable excludes beta and beta includes newest stable or prerelease',
    () async {
      final input = [release(17, beta: true), release(16)];
      expect((await check(input)).candidate!.versionCode, 16);
      expect(
        (await check(
          input,
          channel: UpdateChannel.beta,
        )).candidate!.versionCode,
        17,
      );
      expect((await check(input, current: 17)).candidate, isNull);
    },
  );
  test(
    'ABI preference selects arm64 independently and universal for ARM32',
    () async {
      expect(
        (await check([release(16)])).candidate!.assets.first.name,
        'app-arm.apk',
      );
      expect(
        (await check(
          [release(16)],
          abis: ['armeabi-v7a'],
        )).candidate!.assets.first.name,
        'app.apk',
      );
      expect((await check([release(16)], abis: ['riscv64'])).candidate, isNull);
    },
  );
  test('invalid manifest is incomplete rather than latest', () async {
    for (final invalid in [
      <String, Object?>{},
      {...manifest(16), 'versionCode': -1},
      {...manifest(16), 'channel': 'beta'},
      {...manifest(16), 'minSdk': 99},
      {
        ...manifest(16),
        'assets': [
          {
            'name': 'app-arm.apk',
            'abis': ['arm64-v8a'],
            'bytes': 2100000000,
            'sha256': 'x',
          },
        ],
      },
    ]) {
      final result = await check([release(16)], response: (_) => invalid);
      expect(result.candidate, isNull);
      expect(result.scopeComplete, isFalse);
    }
    final current = await check([release(16)], current: 16);
    expect(current.candidate, isNull);
    expect(current.scopeComplete, isTrue);
  });
  test(
    'explicit binary archives do not make update checks incomplete',
    () async {
      final archive = {
        ...release(4),
        'tag_name': 'v1.2.1',
        'body': '[xdl-archive]\nHistorical binaries, no update manifest.',
        'assets': <Object?>[],
      };
      final result = await check([archive, release(16)], current: 16);
      expect(result.candidate, isNull);
      expect(result.scopeComplete, isTrue);
      expect(result.validReleases, 1);
      final missing = await check([
        {...archive, 'body': 'Ordinary release'},
      ]);
      expect(missing.scopeComplete, isFalse);
    },
  );
  test('rejects off-repository asset and duplicate names', () async {
    final bad = release(16);
    final assets = bad['assets'] as List;
    (assets.first as Map)['browser_download_url'] =
        'https://evil.example/update.json';
    expect((await check([bad])).scopeComplete, isFalse);
    final duplicate = release(16);
    (duplicate['assets'] as List).add((duplicate['assets'] as List).last);
    expect((await check([duplicate])).candidate, isNull);
  });
  test(
    'pagination scans at most 100 and ignores hostile Link headers',
    () async {
      var count = 0;
      final client = GitHubReleaseClient(
        client: MockClient((request) async {
          count++;
          expect(request.url.host, 'api.github.com');
          return http.Response(
            jsonEncode(List.generate(30, (i) => {'draft': true})),
            200,
            headers: {'link': '<https://evil.example/?page=2>; rel="next"'},
          );
        }),
      );
      try {
        final result = await client.check(
          installed: installed(),
          channel: UpdateChannel.beta,
        );
        expect(count, 4);
        expect(result.scopeComplete, isFalse);
      } finally {
        client.close();
      }
    },
  );
  test('rate limit is reported and redirect host is checked', () async {
    for (final status in [403, 429]) {
      final client = GitHubReleaseClient(
        client: MockClient((_) async => http.Response('', status)),
      );
      await expectLater(
        client.check(installed: installed(), channel: UpdateChannel.stable),
        throwsA(isA<Exception>()),
      );
      client.close();
    }
    final client = GitHubReleaseClient(
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/a'},
        ),
      ),
    );
    await expectLater(
      client.check(installed: installed(), channel: UpdateChannel.stable),
      throwsA(isA<Exception>()),
    );
    client.close();
  });
  test('unknown channel is skipped and not fatal', () async {
    final result = await check([
      release(16),
    ], response: (_) => {...manifest(16), 'channel': 'unknown'});
    expect(result.scopeComplete, isFalse);
    expect(result.candidate, isNull);
  });
  test('unordered releases choose greatest validated build code', () async {
    final newer = release(19);
    newer['tag_name'] = 'v2.5.1';
    newer['html_url'] =
        'https://github.com/ThermalEX/XDownloader/releases/tag/v2.5.1';
    for (final asset in newer['assets'] as List) {
      (asset as Map)['browser_download_url'] =
          (asset['browser_download_url'] as String).replaceAll(
            'v2.5.0',
            'v2.5.1',
          );
    }
    final result = await check(
      [newer, release(16)],
      response: (uri) => uri.path.contains('v2.5.1')
          ? {...manifest(19), 'versionName': '2.5.1'}
          : manifest(16),
    );
    expect(result.candidate!.versionCode, 19);
  });
  test('metadata limit rejects an unbounded API response', () async {
    final client = GitHubReleaseClient(
      client: MockClient(
        (_) async => http.Response(' ' * (1024 * 1024 + 1), 200),
      ),
    );
    await expectLater(
      client.check(installed: installed(), channel: UpdateChannel.stable),
      throwsA(isA<FormatException>()),
    );
    client.close();
  });
  test('request timeout aborts rather than waiting indefinitely', () {
    fakeAsync((time) {
      final client = GitHubReleaseClient(
        client: MockClient((_) => Completer<http.Response>().future),
      );
      Object? error;
      client
          .check(installed: installed(), channel: UpdateChannel.stable)
          .then<void>(
            (_) => fail('must time out'),
            onError: (Object e) => error = e,
          );
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 16));
      time.flushMicrotasks();
      expect(error, isA<TimeoutException>());
      client.close();
    });
  });
}

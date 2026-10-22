import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/models/app_failure.dart';
import '../../core/models/app_update.dart';

class GitHubReleaseClient {
  GitHubReleaseClient({required this.client});
  final http.Client client;
  static const repository = 'ThermalEX/XDownloader';
  static final repositoryPage = Uri.https('github.com', '/$repository');
  static final releasesPage = Uri.https('github.com', '/$repository/releases');
  bool _closed = false;
  Completer<void>? _abort;

  static bool isAssetUrl(Uri url, {String? tag, String? name}) {
    if (!_secure(url) || url.host != 'github.com') return false;
    final parts = url.pathSegments;
    return parts.length == 6 &&
        parts.take(4).join('/') == '$repository/releases/download' &&
        parts[4].isNotEmpty &&
        (tag == null || parts[4] == tag) &&
        parts[5].isNotEmpty &&
        (name == null || parts[5] == name) &&
        !url.hasQuery;
  }

  static bool _secure(Uri url) =>
      url.scheme == 'https' &&
      url.userInfo.isEmpty &&
      url.port == 443 &&
      !url.hasFragment;
  bool _allowed(Uri url, {required bool api}) =>
      _secure(url) &&
      (api
          ? url.host == 'api.github.com' &&
                url.path == '/repos/$repository/releases'
          : isAssetUrl(url) ||
                const [
                  'release-assets.githubusercontent.com',
                  'objects.githubusercontent.com',
                ].contains(url.host));

  Future<Object?> _json(
    Uri url, {
    required bool api,
    required Completer<void> abort,
  }) async {
    final limit = api ? 1024 * 1024 : 512 * 1024;
    var target = url;
    for (var hop = 0; hop <= 5; hop++) {
      if (_closed || abort.isCompleted) {
        throw const AppFailure(FailureKind.cancelled, '更新检查已取消');
      }
      if (!_allowed(target, api: api)) {
        throw const FormatException('Untrusted update URL');
      }
      final request = http.AbortableRequest(
        'GET',
        target,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll({
        'Accept': api ? 'application/vnd.github+json' : 'application/json',
        'User-Agent': 'XDownloader-App-Updates',
      });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        // Cancel the response subscription instead of consuming an unbounded body.
        await response.stream.listen((_) {}).cancel();
        if (location == null) throw const FormatException('Missing redirect');
        target = target.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw AppFailure(
          FailureKind.network,
          [403, 429].contains(response.statusCode)
              ? 'GitHub 请求过于频繁，请稍后重试'
              : '无法获取更新信息（${response.statusCode}）',
        );
      }
      if ((response.contentLength ?? 0) > limit) {
        await response.stream.listen((_) {}).cancel();
        throw const FormatException('Update metadata too large');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Update metadata too large');
        }
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes));
    }
    throw const FormatException('Too many update redirects');
  }

  Future<ReleaseCheck> check({
    required InstalledAppInfo installed,
    required UpdateChannel channel,
  }) async {
    cancelCheck();
    final abort = _abort = Completer<void>();
    try {
      return await _check(
        installed,
        channel,
        abort,
      ).timeout(const Duration(seconds: 60));
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
    }
  }

  Future<ReleaseCheck> _check(
    InstalledAppInfo installed,
    UpdateChannel channel,
    Completer<void> abort,
  ) async {
    var scanned = 0, skipped = 0, valid = 0;
    var complete = true;
    UpdateRelease? best;
    for (var page = 1; scanned < 100; page++) {
      final raw = await _json(
        Uri.https('api.github.com', '/repos/$repository/releases', {
          'per_page': '30',
          'page': '$page',
        }),
        api: true,
        abort: abort,
      );
      if (raw is! List) {
        throw const FormatException('Invalid releases response');
      }
      for (final item in raw.take(100 - scanned)) {
        scanned++;
        try {
          final r = Map<String, Object?>.from(item as Map);
          if (r['draft'] == true ||
              (channel == UpdateChannel.stable && r['prerelease'] == true)) {
            continue;
          }
          final assets = r['assets'] as List;
          if ((r['body'] as String? ?? '')
                  .split('\n')
                  .any((line) => line.trim() == '[xdl-archive]') &&
              !assets.any((asset) => (asset as Map)['name'] == 'update.json')) {
            continue;
          }
          final candidate = await _release(r, installed, abort);
          valid++;
          if (candidate.versionCode > installed.versionCode &&
              (best == null || candidate.versionCode > best.versionCode)) {
            best = candidate;
          }
        } on AppFailure catch (_) {
          skipped++;
        } on FormatException catch (_) {
          skipped++;
        } on TypeError catch (_) {
          skipped++;
        }
      }
      if (raw.length < 30) break;
      if (scanned >= 100) complete = false;
    }
    return ReleaseCheck(
      candidate: best,
      scopeComplete: complete && skipped == 0,
      skippedReleases: skipped,
      validReleases: valid,
    );
  }

  Future<UpdateRelease> _release(
    Map<String, Object?> r,
    InstalledAppInfo installed,
    Completer<void> abort,
  ) async {
    final tag = r['tag_name'] as String;
    final entries = <String, Map<String, Object?>>{};
    for (final item in r['assets'] as List) {
      final asset = Map<String, Object?>.from(item as Map),
          name = (item)['name'] as String;
      if (entries.containsKey(name)) {
        throw const FormatException('Duplicate release asset');
      }
      entries[name] = asset;
    }
    Uri assetUrl(String name) {
      final a = entries[name];
      if (a == null || a['state'] != 'uploaded') {
        throw const FormatException('Missing release asset');
      }
      final url = Uri.parse(a['browser_download_url'] as String);
      if (!isAssetUrl(url, tag: tag, name: name)) {
        throw const FormatException('Invalid asset URL');
      }
      return url;
    }

    final m = Map<String, Object?>.from(
      await _json(assetUrl('update.json'), api: false, abort: abort) as Map,
    );
    final version = m['versionName'] as String,
        code = m['versionCode'] as int,
        minSdk = m['minSdk'] as int;
    final channel = switch (m['channel']) {
      'stable' => UpdateChannel.stable,
      'beta' => UpdateChannel.beta,
      _ => throw const FormatException('Unknown update channel'),
    };
    if (m['schema'] != 1 ||
        code <= 0 ||
        minSdk < 26 ||
        minSdk > installed.sdkInt ||
        m['packageName'] != installed.packageName ||
        tag != 'v$version' ||
        (channel == UpdateChannel.beta) != (r['prerelease'] == true) ||
        !RegExp(r'^\d+\.\d+\.\d+(?:-beta\.\d+)?$').hasMatch(version) ||
        (channel == UpdateChannel.beta) != version.contains('-beta.')) {
      throw const FormatException('Inconsistent release metadata');
    }
    final assets = <UpdateAsset>[];
    final names = <String>{};
    for (final raw in m['assets'] as List) {
      final a = Map<String, Object?>.from(raw as Map),
          name = (raw)['name'] as String;
      if (!names.add(name)) {
        throw const FormatException('Duplicate manifest asset');
      }
      final asset = UpdateAsset.fromJson({
        ...a,
        'url': assetUrl(name).toString(),
      });
      if (entries[name]!['size'] != asset.bytes) {
        throw const FormatException('Asset length mismatch');
      }
      if (installed.supportedAbis.any(asset.abis.contains)) assets.add(asset);
    }
    if (assets.isEmpty) throw const FormatException('No compatible APK');
    int rank(UpdateAsset a) {
      final abi = installed.supportedAbis.indexWhere(a.abis.contains);
      return abi * 10 + (a.abis.length == 1 ? 0 : 1);
    }

    assets.sort((a, b) => rank(a).compareTo(rank(b)));
    final page = Uri.parse(r['html_url'] as String);
    if (page != Uri.https('github.com', '/$repository/releases/tag/$tag')) {
      throw const FormatException('Invalid release page');
    }
    return UpdateRelease(
      releaseId: r['id'] as int,
      tag: tag,
      releasePage: page,
      notes: r['body'] as String? ?? '',
      title: r['name'] is String ? (r['name'] as String).trim() : '',
      versionName: version,
      versionCode: code,
      channel: channel,
      packageName: installed.packageName,
      minSdk: minSdk,
      assets: List.unmodifiable(assets),
    );
  }

  void close() {
    _closed = true;
    cancelCheck();
    client.close();
  }

  void cancelCheck() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Non-secret account settings. Passwords belong in platform secure storage.
class WebDavConfig {
  WebDavConfig({
    required Uri endpoint,
    required this.username,
    this.folder = 'XDownloader',
    this.allowHttp = false,
  }) : endpoint = _validateEndpoint(endpoint, allowHttp) {
    _folderSegments(folder);
    if (username.contains(':') || _hasControls(username)) {
      throw ArgumentError('WebDAV 用户名不能包含冒号或控制字符');
    }
  }

  factory WebDavConfig.fromJson(Map<String, Object?> json) => WebDavConfig(
    endpoint: Uri.parse(json['endpoint'] as String),
    username: json['username'] as String,
    folder: json['folder'] as String? ?? 'XDownloader',
    allowHttp: json['allowHttp'] as bool? ?? false,
  );

  final Uri endpoint;
  final String username;
  final String folder;
  final bool allowHttp;

  Map<String, Object?> toJson() => {
    'endpoint': endpoint.toString(),
    'username': username,
    'folder': folder,
    'allowHttp': allowHttp,
  };

  Uri get _directory => endpoint.replace(
    pathSegments: [
      ...endpoint.pathSegments.where((part) => part.isNotEmpty),
      ..._folderSegments(folder),
      '',
    ],
  );

  static Uri _validateEndpoint(Uri endpoint, bool allowHttp) {
    if ((!allowHttp && endpoint.scheme != 'https') ||
        (endpoint.scheme != 'https' && endpoint.scheme != 'http') ||
        !endpoint.hasAuthority ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.pathSegments.any((part) => !_safeComponent(part))) {
      throw ArgumentError('WebDAV 地址必须是无凭据、参数和越界路径的 HTTPS 地址');
    }
    return endpoint.replace(
      pathSegments: [
        ...endpoint.pathSegments.where((part) => part.isNotEmpty),
        '',
      ],
    );
  }

  static List<String> _folderSegments(String folder) {
    final parts = folder.split('/');
    if (parts.any((part) => part.isEmpty || !_safeComponent(part))) {
      throw ArgumentError('WebDAV 文件夹必须使用有效的相对路径');
    }
    return parts;
  }
}

class WebDavEntry {
  const WebDavEntry({
    required this.uri,
    required this.name,
    this.modifiedAt,
    this.bytes,
    this.etag,
  });

  final Uri uri;
  final String name;
  final DateTime? modifiedAt;
  final int? bytes;
  final String? etag;

  /// A change-detection hint, never a substitute for archive validation.
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            uri.toString(),
            if (etag != null)
              etag
            else ...[
              modifiedAt?.toUtc().toIso8601String(),
              bytes,
            ],
          ]),
        ),
      )
      .toString();
}

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Bounded, redirect-free WebDAV transport for immutable archive files.
class WebDavClient {
  WebDavClient({
    required this.config,
    required String password,
    http.Client? client,
    bool Function()? isCancelled,
  }) : _client = client ?? http.Client(),
       _authorization =
           'Basic ${base64Encode(utf8.encode('${config.username}:$password'))}',
       _isCancelled = isCancelled ?? _neverCancelled;

  static const maxArchiveBytes = 16 * 1024 * 1024;
  static const maxListingBytes = 8 * 1024 * 1024;
  static const maxEntries = 1000;
  static const _timeout = Duration(seconds: 30);
  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getlastmodified/><d:getcontentlength/><d:getetag/>'
      '</d:prop></d:propfind>';

  final WebDavConfig config;
  final http.Client _client;
  final String _authorization;
  final bool Function() _isCancelled;
  final Set<Completer<void>> _active = {};
  bool _closed = false;

  static bool _neverCancelled() => false;

  void _check() {
    if (_closed || _isCancelled()) {
      throw const WebDavException('WebDAV 操作已取消');
    }
  }

  Future<List<WebDavEntry>> list() async {
    final result = await _request(
      'PROPFIND',
      config._directory,
      expected: const {207},
      maxBytes: maxListingBytes,
      headers: const {
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      body: utf8.encode(_propfindBody),
    );
    final document = _parseListing(result.body);
    final root = document.rootElement;
    final entries = <String, WebDavEntry>{};
    var count = 0;
    for (final item in root.childElements.where((e) => _isDav(e, 'response'))) {
      _check();
      final href = _davChild(item, 'href')?.innerText.trim();
      if (href == null) continue;
      final uri = _listedUri(href);
      if (uri == config._directory) continue;
      if (++count > maxEntries) {
        throw const WebDavException('WebDAV 目录超过 1000 条限制');
      }
      if (uri == null) continue;
      final properties = <String, XmlElement>{};
      for (final propstat in item.childElements.where(
        (e) => _isDav(e, 'propstat'),
      )) {
        final status = _davChild(propstat, 'status')?.innerText;
        if (!_successfulStatus(status)) continue;
        final prop = _davChild(propstat, 'prop');
        if (prop == null) continue;
        for (final child in prop.childElements) {
          if (child.name.namespaceUri == 'DAV:') {
            properties[child.name.local] = child;
          }
        }
      }
      if (properties.isEmpty ||
          properties['resourcetype']?.childElements.any(
                (e) => _isDav(e, 'collection'),
              ) ==
              true) {
        continue;
      }
      final name = uri.pathSegments.last;
      if (!_archiveName(name)) continue;
      final etag = properties['getetag']?.innerText.trim();
      final length = int.tryParse(
        properties['getcontentlength']?.innerText.trim() ?? '',
      );
      entries[uri.toString()] = WebDavEntry(
        uri: uri,
        name: name,
        modifiedAt: _date(properties['getlastmodified']?.innerText.trim()),
        bytes: length != null && length >= 0 ? length : null,
        etag: etag != null && etag.isNotEmpty && !_hasControls(etag)
            ? etag
            : null,
      );
    }
    _check();
    return List.unmodifiable(entries.values);
  }

  Future<List<int>> read(WebDavEntry entry) async {
    final result = await _readEntry(entry);
    return result.body;
  }

  Future<_DavResponse> _readEntry(WebDavEntry entry, {bool probe = false}) {
    _validateEntry(entry, probe: probe);
    return _request(
      'GET',
      entry.uri,
      expected: const {200},
      maxBytes: maxArchiveBytes,
    );
  }

  Future<WebDavEntry> upload(
    String name,
    List<int> bytes, {
    bool reconcileExisting = false,
  }) async {
    _check();
    if (!_archiveName(name)) throw const WebDavException('无效的云端存档文件名');
    if (bytes.length > maxArchiveBytes) {
      throw const WebDavException('存档超过 16 MiB 限制');
    }
    // Snapshot mutable input before the first await.
    final data = Uint8List.fromList(bytes);
    await _ensureFolders();
    return _upload(name, data, reconcileExisting: reconcileExisting);
  }

  Future<WebDavEntry> _upload(
    String name,
    List<int> bytes, {
    bool probe = false,
    bool reconcileExisting = false,
  }) async {
    final entry = WebDavEntry(
      uri: config._directory.resolveUri(Uri(pathSegments: [name])),
      name: name,
    );
    try {
      await _request(
        'PUT',
        entry.uri,
        expected: const {200, 201, 204},
        maxBytes: 64 * 1024,
        headers: const {
          'If-None-Match': '*',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: bytes,
      );
    } on WebDavException catch (error) {
      // An explicit retry can reconcile a previously accepted upload whose
      // verification failed. It still never overwrites any existing bytes.
      if (!probe && reconcileExisting && error.statusCode == 412) {
        _check();
        return _verifyUpload(entry, bytes);
      }
      // Ordinary creations and connection probes always treat 412 as conflict.
      if (error.statusCode != null && error.statusCode! < 500) rethrow;
      _check();
      return _verifyUpload(entry, bytes, probe: probe);
    }
    return _verifyUpload(entry, bytes, probe: probe);
  }

  Future<WebDavEntry> _verifyUpload(
    WebDavEntry entry,
    List<int> bytes, {
    bool probe = false,
  }) async {
    final result = await _readEntry(entry, probe: probe);
    if (sha256.convert(result.body) != sha256.convert(bytes)) {
      throw const WebDavException('上传后的云端文件校验失败；本地存档仍可保留重试');
    }
    _check();
    return WebDavEntry(
      uri: entry.uri,
      name: entry.name,
      bytes: result.body.length,
      modifiedAt: _date(result.headers['last-modified']),
      etag: _safeEtag(result.headers['etag']),
    );
  }

  Future<void> delete(WebDavEntry entry) => _deleteEntry(entry);

  Future<void> _deleteEntry(WebDavEntry entry, {bool probe = false}) async {
    _validateEntry(entry, probe: probe);
    await _request(
      'DELETE',
      entry.uri,
      expected: const {200, 204},
      maxBytes: 64 * 1024,
      headers: {if (entry.etag != null) 'If-Match': entry.etag!},
    );
  }

  Future<void> testConnection() async {
    _check();
    await _ensureFolders();
    final random = Random.secure();
    final token = List.generate(24, (_) => random.nextInt(256));
    final name =
        '.xdl-connection-${token.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}.tmp';
    final bytes = utf8.encode(
      'XDownloader WebDAV connection test ${base64Encode(token)}',
    );
    final target = WebDavEntry(
      uri: config._directory.resolveUri(Uri(pathSegments: [name])),
      name: name,
    );
    WebDavEntry? created;
    try {
      // Only a confirmed conditional creation owns the probe and permits cleanup.
      await _request(
        'PUT',
        target.uri,
        expected: const {201},
        maxBytes: 64 * 1024,
        headers: const {
          'If-None-Match': '*',
          'Content-Type': 'text/plain; charset=utf-8',
        },
        body: bytes,
      );
      created = target;
      created = await _verifyUpload(target, bytes, probe: true);
    } finally {
      // Do not initiate new network work after privacy cancellation. A server
      // may retain the random probe when cancellation or a network failure hits.
      if (created != null && !_closed && !_isCancelled()) {
        try {
          await _deleteEntry(created, probe: true);
        } on WebDavException catch (error) {
          _check();
          // Retry only uncertain/transient cleanup, using the same random path
          // and verified ETag. Never retry a definite permission/conflict error.
          if (error.statusCode != null && error.statusCode! < 500) rethrow;
          await _deleteEntry(created, probe: true);
        }
      }
    }
  }

  Future<void> _ensureFolders() async {
    final prefix = config.endpoint.pathSegments
        .where((p) => p.isNotEmpty)
        .toList();
    for (final part in WebDavConfig._folderSegments(config.folder)) {
      prefix.add(part);
      final directory = config.endpoint.replace(pathSegments: [...prefix, '']);
      final result = await _request(
        'MKCOL',
        directory,
        expected: const {200, 201, 204, 405},
        maxBytes: 64 * 1024,
      );
      if (result.statusCode == 405) {
        final existing = await _request(
          'PROPFIND',
          directory,
          expected: const {207},
          maxBytes: maxListingBytes,
          headers: const {
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          body: utf8.encode(_propfindBody),
        );
        final document = _parseListing(existing.body);
        var collection = false;
        for (final item in document.rootElement.childElements.where(
          (e) => _isDav(e, 'response'),
        )) {
          final href = _davChild(item, 'href')?.innerText.trim();
          if (href == null) continue;
          final given = Uri.tryParse(href);
          if (given == null ||
              given.hasQuery ||
              given.hasFragment ||
              given.userInfo.isNotEmpty ||
              given.pathSegments.any((p) => !_safeComponent(p))) {
            continue;
          }
          final target = directory.resolveUri(given);
          if (target != directory) continue;
          for (final propstat in item.childElements.where(
            (e) => _isDav(e, 'propstat'),
          )) {
            if (!_successfulStatus(_davChild(propstat, 'status')?.innerText)) {
              continue;
            }
            final prop = _davChild(propstat, 'prop');
            final type = prop == null ? null : _davChild(prop, 'resourcetype');
            if (type?.childElements.any((e) => _isDav(e, 'collection')) ==
                true) {
              collection = true;
            }
          }
        }
        _check();
        if (!collection) throw const WebDavException('WebDAV 目标路径不是有效的目录');
      }
    }
  }

  void _validateEntry(WebDavEntry entry, {bool probe = false}) {
    _check();
    final safe = _listedUri(entry.uri.toString());
    if (safe == null ||
        safe != entry.uri ||
        safe == config._directory ||
        safe.pathSegments.last != entry.name ||
        !(probe
            ? entry.name.startsWith('.xdl-connection-') &&
                  entry.name.endsWith('.tmp')
            : _archiveName(entry.name)) ||
        (entry.etag != null && _hasControls(entry.etag!))) {
      throw const WebDavException('云端文件必须位于当前 WebDAV 存档目录内');
    }
  }

  Uri? _listedUri(String href) {
    try {
      final given = Uri.parse(href);
      if (given.userInfo.isNotEmpty ||
          given.hasQuery ||
          given.hasFragment ||
          given.pathSegments.any((part) => !_safeComponent(part))) {
        return null;
      }
      final uri = config._directory.resolveUri(given);
      final directory = config._directory;
      if (uri.scheme != directory.scheme ||
          uri.host != directory.host ||
          uri.port != directory.port ||
          uri.userInfo.isNotEmpty) {
        return null;
      }
      if (uri == directory) return directory;
      final parent = directory.pathSegments.where((p) => p.isNotEmpty).toList();
      final segments = uri.pathSegments;
      if (segments.length != parent.length + 1 || segments.last.isEmpty) {
        return null;
      }
      for (var i = 0; i < parent.length; i++) {
        if (segments[i] != parent[i]) return null;
      }
      return directory.replace(pathSegments: [...parent, segments.last]);
    } on FormatException {
      return null;
    }
  }

  Future<_DavResponse> _request(
    String method,
    Uri uri, {
    required Set<int> expected,
    required int maxBytes,
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    _check();
    final abort = Completer<void>();
    _active.add(abort);
    final stopped = Completer<_DavResponse>();
    Timer? cancellationTimer;
    Timer? timeoutTimer;
    void stop(WebDavException reason) {
      if (!abort.isCompleted) abort.complete();
      if (!stopped.isCompleted) stopped.completeError(reason);
    }

    cancellationTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_closed || _isCancelled()) {
        stop(const WebDavException('WebDAV 操作已取消'));
      }
    });
    timeoutTimer = Timer(
      _timeout,
      () => stop(const WebDavException('WebDAV 操作超时，请重试')),
    );
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers.addAll({
            'Authorization': _authorization,
            'Accept-Encoding': 'identity',
            ...headers,
          });
    if (body != null) request.bodyBytes = body;
    Future<_DavResponse> send() async {
      http.StreamedResponse? response;
      try {
        response = await _client.send(request);
        _check();
        if (!expected.contains(response.statusCode)) {
          await response.stream.listen(null).cancel();
          throw WebDavException(
            response.statusCode >= 300 && response.statusCode < 400
                ? 'WebDAV 不接受跳转，请使用服务器的最终地址'
                : response.statusCode == 412
                ? '云端文件已存在或已更改，未覆盖文件'
                : 'WebDAV 请求失败（HTTP ${response.statusCode}）',
            statusCode: response.statusCode,
          );
        }
        if (response.headers.containsKey('content-range')) {
          await response.stream.listen(null).cancel();
          throw const WebDavException('WebDAV 返回了不完整的分段响应');
        }
        final declaredHeader = response.headers['content-length'];
        final declared = declaredHeader == null
            ? response.contentLength
            : int.tryParse(declaredHeader);
        if ((declaredHeader != null && declared == null) ||
            (declared != null && (declared < 0 || declared > maxBytes))) {
          await response.stream.listen(null).cancel();
          throw const WebDavException('WebDAV 响应超过大小限制或长度无效');
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          _check();
          if (abort.isCompleted) throw const WebDavException('WebDAV 操作已取消或超时');
          if (builder.length + chunk.length > maxBytes) {
            throw const WebDavException('WebDAV 响应超过大小限制');
          }
          builder.add(chunk);
        }
        _check();
        if (declared != null && builder.length != declared) {
          throw const WebDavException('WebDAV 响应不完整，长度不符');
        }
        return _DavResponse(
          builder.takeBytes(),
          response.headers,
          response.statusCode,
        );
      } on WebDavException {
        rethrow;
      } catch (_) {
        // Transport exception strings may contain credential-bearing request
        // details. Expose a fixed message instead of propagating them to UI.
        throw const WebDavException('WebDAV 网络请求失败，请检查连接后重试');
      }
    }

    unawaited(
      send().then(
        (value) {
          if (!stopped.isCompleted) stopped.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!stopped.isCompleted) stopped.completeError(error, stack);
        },
      ),
    );
    try {
      return await stopped.future;
    } finally {
      cancellationTimer.cancel();
      timeoutTimer.cancel();
      _active.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  void close() {
    _closed = true;
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
  }
}

class _DavResponse {
  _DavResponse(this.body, this.headers, this.statusCode);
  final Uint8List body;
  final Map<String, String> headers;
  final int statusCode;
}

XmlDocument _parseListing(List<int> bytes) {
  final text = utf8.decode(bytes);
  final upper = text.toUpperCase();
  if (upper.contains('<!DOCTYPE') || upper.contains('<!ENTITY')) {
    throw const WebDavException('WebDAV 目录 XML 不允许文档类型或外部实体');
  }
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlParserException {
    throw const WebDavException('WebDAV 返回了无效的目录 XML');
  }
  if (!_isDav(document.rootElement, 'multistatus')) {
    throw const WebDavException('WebDAV 未返回有效的多状态目录');
  }
  return document;
}

bool _safeComponent(String component) {
  var value = component;
  // Repeated decoding rejects double-encoded traversal and separator tricks.
  for (var i = 0; i < 8; i++) {
    if (value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\') ||
        _hasControls(value)) {
      return false;
    }
    if (!value.contains('%')) return true;
    try {
      final decoded = Uri.decodeComponent(value);
      if (decoded == value) return true;
      value = decoded;
    } on ArgumentError {
      return false;
    }
  }
  return false;
}

bool _hasControls(String value) =>
    value.codeUnits.any((unit) => unit < 32 || unit == 127);

bool _archiveName(String name) =>
    name.isNotEmpty &&
    name.length <= 240 &&
    _safeComponent(name) &&
    name.endsWith('.xdlbackup.json');

bool _isDav(XmlElement element, String local) =>
    element.name.local == local && element.name.namespaceUri == 'DAV:';

XmlElement? _davChild(XmlElement parent, String name) {
  for (final child in parent.childElements) {
    if (_isDav(child, name)) return child;
  }
  return null;
}

bool _successfulStatus(String? status) {
  if (status == null) return false;
  final parts = status.trim().split(RegExp(r'\s+'));
  final code = parts.length >= 2 ? int.tryParse(parts[1]) : null;
  return parts.first.startsWith('HTTP/') &&
      code != null &&
      code >= 200 &&
      code < 300;
}

DateTime? _date(String? value) {
  if (value == null) return null;
  try {
    return HttpDate.parse(value).toUtc();
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}

String? _safeEtag(String? etag) =>
    etag != null && etag.isNotEmpty && !_hasControls(etag) ? etag : null;

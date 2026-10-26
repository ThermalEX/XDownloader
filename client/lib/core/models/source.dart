enum SourceKind { xdl, fx, syndication, vx, scrape, snap, tweetdl, twmate }

class ParseSource {
  const ParseSource(
    this.id,
    this.name,
    this.endpoint,
    this.kind,
    this.method,
    this.body,
    this.builtin,
  );
  final String id, name, endpoint, method, body;
  final SourceKind kind;
  final bool builtin;
  String get requestMethod => switch (kind) {
    SourceKind.xdl ||
    SourceKind.snap ||
    SourceKind.tweetdl ||
    SourceKind.twmate => 'POST',
    SourceKind.scrape => method.toUpperCase(),
    _ => 'GET',
  };
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'kind': kind.name,
    'method': method,
    'body': body,
    'builtin': builtin,
  };
  factory ParseSource.fromJson(Map<String, dynamic> m) => ParseSource(
    m['id'] as String,
    m['name'] as String,
    m['endpoint'] as String,
    SourceKind.values.byName(m['kind'] as String),
    m['method'] as String? ?? 'GET',
    m['body'] as String? ?? '',
    m['builtin'] == true,
  );
}

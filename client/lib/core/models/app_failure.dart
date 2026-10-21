enum FailureKind {
  invalidLink,
  network,
  timeout,
  noVideo,
  server,
  malformed,
  cancelled,
  storage,
  fileMissing,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, [this.details]);
  final FailureKind kind;
  final String message;
  final String? details;
  @override
  String toString() => details == null ? message : '$message ($details)';
}

import 'package:flutter/services.dart';

typedef PlatformCall = Future<Object?> Function(
  String method,
  Map<String, Object?> arguments,
);
const platformChannel = MethodChannel('xdl/platform');
Future<Object?> callPlatform(String method, Map<String, Object?> arguments) =>
    platformChannel.invokeMethod(method, arguments);

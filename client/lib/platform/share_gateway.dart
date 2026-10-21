import 'package:flutter/services.dart';

import 'platform_bridge.dart';

class ShareGateway {
  ShareGateway({PlatformCall? call, Stream<Object?>? events})
    : call = call ?? callPlatform,
      events =
          events ??
          const EventChannel('xdl/shared_text').receiveBroadcastStream();
  final PlatformCall call;
  final Stream<Object?> events;
  bool _initialConsumed = false;
  Future<String?> initialText() async {
    if (_initialConsumed) return null;
    _initialConsumed = true;
    try {
      final text = await call('initialShare', {});
      return text is String && text.trim().isNotEmpty ? text.trim() : null;
    } catch (_) {
      _initialConsumed = false;
      rethrow;
    }
  }

  Stream<String> get sharedText => events
      .where((e) => e is String && e.trim().isNotEmpty)
      .cast<String>()
      .map((e) => e.trim());
}

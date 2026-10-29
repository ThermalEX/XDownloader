import 'dart:math';

import '../models/request_rotation.dart';

/// Lightweight HTTP headers only. Does not change TLS, IP or browser APIs.
class RequestProfiles {
  RequestProfiles({DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random();
  final DateTime Function() _now;
  final Random _random;
  Map<String, RequestRotation> _policies = {};
  final _sessions = <String, _ProfileSession>{};
  final _cooldowns = <String, DateTime>{};
  static const _platforms = [
    'Linux; Android 10; K',
    'Windows NT 10.0; Win64; x64',
    'X11; Linux x86_64',
  ];

  RequestRotation policyFor(String id) =>
      _policies[id] ?? const RequestRotation();
  void configure(Map<String, RequestRotation> policies) {
    for (final policy in policies.values) {
      policy.validate();
    }
    _sessions.removeWhere((id, _) {
      final a = policyFor(id), b = policies[id] ?? const RequestRotation();
      return a.mode != b.mode || a.interval != b.interval;
    });
    _policies = Map.of(policies);
  }

  RequestProfileAttempt begin(String id) {
    final policy = policyFor(id);
    if (policy.mode == RotationMode.off) {
      return RequestProfileAttempt._(id, null);
    }
    final now = _now();
    final old = _sessions[id];
    final rotate =
        old == null ||
        switch (policy.mode) {
          RotationMode.off => false,
          RotationMode.minutes =>
            now.difference(old.created).inMinutes >= policy.interval,
          RotationMode.count => old.completed >= policy.interval,
        };
    if (rotate) {
      final index = old == null
          ? _random.nextInt(_platforms.length)
          : (old.index + 1 + _random.nextInt(_platforms.length - 1)) %
                _platforms.length;
      _sessions[id] = _ProfileSession(
        index,
        now,
        Map.unmodifiable({
          'user-agent':
              'Mozilla/5.0 (${_platforms[index]}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0${index == 0 ? ' Mobile' : ''} Safari/537.36',
          'accept-language': const [
            'zh-CN,zh;q=0.9,en;q=0.8',
            'en-US,en;q=0.9',
            'en-GB,en;q=0.9',
          ][index],
        }),
      );
    }
    return RequestProfileAttempt._(id, _sessions[id]);
  }

  void complete(RequestProfileAttempt attempt) {
    if (attempt._completed) return;
    attempt._completed = true;
    final session = attempt._session;
    if (session != null && identical(_sessions[attempt.sourceId], session)) {
      session.completed++;
    }
  }

  Duration cooldownRemaining(String id) {
    final until = _cooldowns[id];
    if (until == null) return Duration.zero;
    final remaining = until.difference(_now());
    if (remaining > Duration.zero) return remaining;
    _cooldowns.remove(id);
    return Duration.zero;
  }

  void recordResponse(String id, int status, Map<String, String> headers) {
    final value = headers['retry-after']?.trim();
    if (status != 429 && !(status == 503 && value != null)) return;
    const maximum = Duration(hours: 24);
    var delay = const Duration(minutes: 2);
    if (value != null) {
      if (RegExp(r'^\d+$').hasMatch(value)) {
        final seconds = int.tryParse(value);
        if (seconds == null || seconds >= maximum.inSeconds) {
          delay = maximum;
        } else if (seconds > 0) {
          delay = Duration(seconds: seconds);
        }
      } else {
        final date = _httpDate(value);
        if (date != null && date.isAfter(_now())) {
          delay = date.difference(_now());
        }
      }
    }
    if (delay > maximum) delay = maximum;
    final until = _now().add(delay);
    if (!(_cooldowns[id]?.isAfter(until) ?? false)) _cooldowns[id] = until;
  }

  // IMF-fixdate, the HTTP-date format emitted by modern servers.
  static DateTime? _httpDate(String text) {
    final match = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(text);
    if (match == null) return null;
    final month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ].indexOf(match[2]!);
    if (month < 0) return null;
    final day = int.parse(match[1]!),
        hour = int.parse(match[4]!),
        minute = int.parse(match[5]!),
        second = int.parse(match[6]!);
    final result = DateTime.utc(
      int.parse(match[3]!),
      month + 1,
      day,
      hour,
      minute,
      second,
    );
    return result.day == day && hour < 24 && minute < 60 && second < 60
        ? result
        : null;
  }

  void forget(String id) => _sessions.remove(id);
  void clear() {
    _policies.clear();
    _sessions.clear();
    _cooldowns.clear();
  }
}

class RequestProfileAttempt {
  RequestProfileAttempt._(this.sourceId, this._session);
  final String sourceId;
  final _ProfileSession? _session;
  bool _completed = false;
  Map<String, String> get headers => _session?.headers ?? const {};
}

class _ProfileSession {
  _ProfileSession(this.index, this.created, this.headers);
  final int index;
  final DateTime created;
  final Map<String, String> headers;
  int completed = 0;
}

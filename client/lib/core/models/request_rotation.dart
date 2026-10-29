enum RotationMode { off, minutes, count }

class RequestRotation {
  const RequestRotation([this.mode = RotationMode.off, this.interval = 15]);
  final RotationMode mode;
  final int interval;
  int get maximum => mode == RotationMode.count ? 1000 : 1440;
  void validate() {
    if (interval < 1 || interval > maximum) {
      throw const FormatException('Invalid request rotation interval');
    }
  }

  String get description => switch (mode) {
    RotationMode.off => '关闭',
    RotationMode.minutes => '每 $interval 分钟',
    RotationMode.count => '每 $interval 次解析',
  };
  Map<String, Object?> toJson() => {'mode': mode.name, 'interval': interval};
  factory RequestRotation.fromJson(Map<String, Object?> json) {
    final name = json['mode'], interval = json['interval'];
    final modes = RotationMode.values.where((m) => m.name == name);
    if (modes.isEmpty || interval is! int) {
      throw const FormatException('Invalid request rotation policy');
    }
    return RequestRotation(modes.single, interval)..validate();
  }
}

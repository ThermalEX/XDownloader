import 'platform_bridge.dart';

/// Window-scoped brightness and the device's media volume, without root.
class PlayerDeviceControls {
  PlayerDeviceControls({this.call = callPlatform});
  final PlatformCall call;
  double brightness = 0.5, volume = 0.5;
  bool volumeFixed = false;
  bool _active = false;

  void _read(Object? raw) {
    final values = raw as Map;
    brightness = (values['brightness'] as num).toDouble();
    volume = (values['volume'] as num).toDouble();
    volumeFixed = values['volumeFixed'] == true;
  }

  Future<void> begin() async {
    _active = true;
    _read(await call('beginPlaybackControls', {}));
  }

  Future<void> refresh() async {
    if (_active) _read(await call('readPlaybackControls', {}));
  }

  Future<double> adjust(bool isBrightness, double value) async {
    final limited = value.clamp(isBrightness ? 0.02 : 0.0, 1.0);
    if (!_active) return isBrightness ? brightness : volume;
    final actual = await call(
      isBrightness ? 'setPlaybackBrightness' : 'setPlaybackVolume',
      {'value': limited},
    );
    final result = (actual as num).toDouble();
    if (isBrightness) {
      brightness = result;
    } else {
      volume = result;
    }
    return result;
  }

  Future<void> fullscreen(bool value) async {
    if (_active) await call('setPlaybackFullscreen', {'value': value});
  }

  Future<void> end() async {
    _active = false;
    await call('endPlaybackControls', {});
  }
}

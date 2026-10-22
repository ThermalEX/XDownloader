import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_update.dart';

void main() {
  test('preferences default stable and round trip local last-check time', () {
    final defaults = UpdatePreferences.fromJson({});
    expect(defaults.channel, UpdateChannel.stable);
    expect(defaults.autoCheck, isTrue);
    expect(defaults.showUpdatePrompt, isTrue);
    final saved = defaults.copyWith(
      channel: UpdateChannel.beta,
      autoCheck: false,
      showUpdatePrompt: false,
      lastAutomaticCheckAt: DateTime(2026, 10, 21, 2),
    );
    final restored = UpdatePreferences.fromJson(saved.toJson());
    expect(restored.channel, UpdateChannel.beta);
    expect(restored.autoCheck, isFalse);
    expect(restored.showUpdatePrompt, isFalse);
    expect(
      restored.lastAutomaticCheckAt!.isAtSameMomentAs(
        saved.lastAutomaticCheckAt!,
      ),
      isTrue,
    );
  });
  test(
    'asset rejects traversal empty ABI invalid hashes and oversized package',
    () {
      final good = <String, Object?>{
        'name': 'app.apk',
        'url': 'https://github.com/ThermalEX/XDownloader/releases/download/v2.5.0/app.apk',
        'abis': ['arm64-v8a'],
        'bytes': 100,
        'sha256': 'a' * 64,
      };
      expect(UpdateAsset.fromJson(good).bytes, 100);
      for (final change in [
        {'name': '../app.apk'},
        {'abis': <String>[]},
        {
          'abis': ['riscv64'],
        },
        {'sha256': 'bad'},
        {'bytes': 0},
        {'bytes': UpdateAsset.maxBytes + 1},
      ]) {
        expect(
          () => UpdateAsset.fromJson({...good, ...change}),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
}

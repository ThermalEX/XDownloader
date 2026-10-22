import 'package:xdownloader/core/models/app_update.dart';

InstalledAppInfo fixtureInstalled({int code = 14}) => InstalledAppInfo(
  packageName: 'com.xdl.app',
  versionName: '2.4.1',
  versionCode: code,
  sdkInt: 37,
  supportedAbis: const ['arm64-v8a'],
);
UpdateRelease fixtureUpdate({
  int code = 15,
  UpdateChannel channel = UpdateChannel.stable,
  String title = '',
  String notes = '新版说明',
}) {
  final version = channel == UpdateChannel.beta ? '2.6.0-beta.1' : '2.5.0';
  final tag = 'v$version';
  return UpdateRelease(
    releaseId: code,
    tag: tag,
    releasePage: Uri.parse(
      'https://github.com/ThermalEX/XDownloader/releases/tag/$tag',
    ),
    title: title,
    notes: notes,
    versionName: version,
    versionCode: code,
    channel: channel,
    packageName: 'com.xdl.app',
    minSdk: 26,
    assets: [
      UpdateAsset(
        name: 'app.apk',
        url: Uri.parse(
          'https://github.com/ThermalEX/XDownloader/releases/download/$tag/app.apk',
        ),
        abis: const ['arm64-v8a'],
        bytes: 80,
        sha256: 'a' * 64,
      ),
    ],
  );
}

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xdownloader/core/models/app_update.dart';
import 'package:xdownloader/data/updates/github_release_client.dart';
import 'package:xdownloader/platform/update_backend.dart';

import 'update_fixture.dart';

class FakeUpdateBackend implements UpdateBackend {
  InstalledAppInfo info = fixtureInstalled();
  UpdateTransfer transfer = const UpdateTransfer();
  Object? readError;
  final calls = <String>[];
  final pages = <Uri>[];
  @override
  Future<InstalledAppInfo> installedApp() async {
    if (readError != null) throw readError!;
    return info;
  }

  @override
  Future<UpdateTransfer> snapshot() async {
    if (readError != null) throw readError!;
    return transfer;
  }

  @override
  Future<void> enqueue(UpdateRelease release, UpdateAsset asset) async {
    calls.add('enqueue');
    transfer = UpdateTransfer(
      candidateId: release.candidateId,
      versionName: release.versionName,
      versionCode: release.versionCode,
      phase: UpdatePhase.running,
      totalBytes: asset.bytes,
    );
  }

  @override
  Future<void> cancel(String candidateId) async {
    calls.add('cancel');
    transfer = UpdateTransfer(
      candidateId: candidateId,
      phase: UpdatePhase.cancelled,
    );
  }

  @override
  Future<UpdateTransfer> requestInstall(String candidateId) async {
    calls.add('install:$candidateId');
    return transfer;
  }

  @override
  Future<void> openReleasePage(Uri url) async {
    pages.add(url);
  }
}

class FixtureReleaseClient extends GitHubReleaseClient {
  FixtureReleaseClient()
    : super(client: MockClient((_) async => http.Response('[]', 200)));
  int checks = 0;
  Future<ReleaseCheck> Function(UpdateChannel)? respond;
  @override
  Future<ReleaseCheck> check({
    required InstalledAppInfo installed,
    required UpdateChannel channel,
  }) async {
    checks++;
    return await respond?.call(channel) ??
        const ReleaseCheck(
          scopeComplete: true,
          skippedReleases: 0,
          validReleases: 0,
        );
  }
}

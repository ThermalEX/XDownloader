import '../core/models/app_update.dart';

abstract interface class UpdateBackend {
  Future<InstalledAppInfo> installedApp();
  Future<UpdateTransfer> snapshot();
  Future<void> enqueue(UpdateRelease release, UpdateAsset asset);
  Future<void> cancel(String candidateId);
  Future<UpdateTransfer> requestInstall(String candidateId);
  Future<void> openReleasePage(Uri url);
}

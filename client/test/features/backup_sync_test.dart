import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/data/backup/backup_archive.dart';
import 'package:xdownloader/data/backup/webdav_client.dart';
import 'package:xdownloader/data/repositories/backup_repository.dart';
import 'package:xdownloader/features/settings/backup_sync_screen.dart';

BackupArchive archive(String id, {bool empty = false, bool all = false}) =>
    BackupArchive.create(
      id: id,
      createdAt: DateTime.utc(2026, 11, 1),
      deviceId: 'device',
      deviceName: '秘密设备-$id',
      appVersion: '2.16.0',
      data: {
        'favorites': {
          'items': empty ? [] : [favorite()],
          'categories': [],
        },
        'settings': {'themeMode': 'dark'},
        if (all) 'sources': {'custom': []},
        if (all) 'updates': {'channel': 'beta'},
      },
    );

Map<String, Object?> favorite() => {
  'postId': '12345',
  'url': 'https://x.com/i/status/12345',
  'title': '秘密收藏',
  'category': '',
  'createdAt': '2026-11-01T00:00:00.000Z',
};

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: brightness,
      ),
      useMaterial3: true,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: BackupSyncScreen(repository: repository),
  ),
);

Future<void> tap(WidgetTester tester, Key key) async {
  // Finish text editing before scrolling the form. Otherwise EditableText's
  // pending show-on-screen request can scroll back to the focused field and
  // dispose a lazily built button between scrollUntilVisible and hit testing.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (find.byKey(key).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.byKey(key),
      240,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
  }
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(find.byKey(key)),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
  expect(find.byKey(key).hitTestable(), findsOneWidget);
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'new server input is empty with a hint instead of prefilled protocol',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      await tap(tester, const Key('backup_config'));
      final field = tester.widget<TextField>(
        find.byKey(const Key('webdav_endpoint')),
      );
      expect(field.controller!.text, isEmpty);
      expect(field.decoration!.hintText, 'https://dav.example.com/dav/');
      expect(field.decoration!.labelText, '服务器地址');
      final hintOpacity = find
          .ancestor(
            of: find.text('https://dav.example.com/dav/'),
            matching: find.byType(AnimatedOpacity),
          )
          .first;
      expect(tester.widget<AnimatedOpacity>(hintOpacity).opacity, 1.0);
    },
  );
  testWidgets(
    'unconfigured backup saves locally and all portable groups are selected',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      await tap(tester, const Key('backup_create'));
      expect(repository.createdLocation, BackupLocation.local);
      expect(repository.createdSections, BackupArchive.sections);
    },
  );

  testWidgets(
    'cloud lists historical files and selecting old file only downloads',
    (tester) async {
      final repository = _Repository()..config = _config;
      await _pump(tester, repository);
      await tap(tester, const Key('backup_cloud'));
      expect(
        find.text(repository.remoteEntries.first.name.replaceFirst('.zip', '')),
        findsOneWidget,
      );
      expect(
        find.text(repository.remoteEntries.last.name.replaceFirst('.zip', '')),
        findsOneWidget,
      );
      expect(find.textContaining('云端修改时间'), findsWidgets);
      expect(find.textContaining('下载校验后查看'), findsWidgets);
      expect(find.textContaining('设备和内容'), findsNothing);
      await tap(
        tester,
        Key('remote_${repository.remoteEntries.last.fingerprint}'),
      );
      await tap(tester, const Key('backup_download'));
      expect(repository.downloaded?.name, repository.remoteEntries.last.name);
      expect(repository.restores, 0);
      expect(repository.before['favorites']!['items'], [favorite()]);
    },
  );

  testWidgets(
    'privacy immediately hides local archive details and restore dialog',
    (tester) async {
      final repository = _Repository()
        ..localArchives = [_Local(archive('old'))];
      await _pump(tester, repository);
      await tap(tester, const Key('backup_local'));
      await tap(tester, const Key('local_old'));
      expect(find.textContaining('秘密设备-old'), findsWidgets);
      await tap(tester, const Key('backup_restore'));
      expect(find.text('恢复选项'), findsOneWidget);
      repository.setPrivacy(true);
      await tester.pump();
      expect(find.textContaining('秘密设备'), findsNothing);
      expect(find.text('恢复选项'), findsNothing);
      expect(find.text('预览变更'), findsNothing);
      expect(find.text('隐私模式下不可查看或备份'), findsWidgets);
      expect(repository.restores, 0);
    },
  );

  testWidgets('privacy hides an open configuration page and cloud metadata', (
    tester,
  ) async {
    final repository = _Repository()..config = _config;
    await _pump(tester, repository);
    await tap(tester, const Key('backup_config'));
    expect(find.text(repository.config!.endpoint.toString()), findsOneWidget);
    repository.setPrivacy(true);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(find.text(repository.config!.endpoint.toString()), findsNothing);
    expect(find.text('隐私模式下不可查看或备份'), findsWidgets);
  });

  testWidgets(
    'restore previews selected sections and confirms clear before applying',
    (tester) async {
      final repository = _Repository()
        ..localArchives = [_Local(archive('empty', empty: true))];
      await _pump(tester, repository);
      await tap(tester, const Key('backup_local'));
      await tap(tester, const Key('local_empty'));
      await tap(tester, const Key('backup_restore'));
      await tap(tester, const Key('restore_mode_replace'));
      await tap(tester, const Key('restore_section_settings'));
      await tap(tester, const Key('restore_preview'));
      expect(repository.previewSections, {'favorites'});
      expect(repository.previewReplace, isTrue);
      expect(repository.restores, 0);
      expect(find.textContaining('将删除 1 条收藏'), findsOneWidget);
      expect(find.textContaining('本地安全存档'), findsOneWidget);
      await tap(tester, const Key('restore_confirm'));
      expect(repository.restores, 1);
    },
  );

  testWidgets(
    'restore uses two full pages, keeps choices on back and omits sync status',
    (tester) async {
      final repository = _Repository()
        ..recentCheckAt = DateTime.utc(2026, 11, 8)
        ..status = '已下载到本地，当前数据未改变'
        ..localArchives = [_Local(archive('all', all: true))];
      await _pump(tester, repository);
      await tap(tester, const Key('backup_local'));
      await tap(tester, const Key('local_all'));
      await tap(tester, const Key('backup_restore'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('最近云端检测'), findsNothing);
      expect(find.text('已下载到本地，当前数据未改变'), findsNothing);
      await tap(tester, const Key('restore_section_settings'));
      await tap(tester, const Key('restore_prefer_archive'));
      final footer = tester.getRect(find.byKey(const Key('restore_preview')));
      expect(footer.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
      await tap(tester, const Key('restore_preview'));
      expect(repository.previewSections, {'favorites', 'sources', 'updates'});
      expect(repository.previewPreferArchive, isTrue);
      expect(repository.restores, 0);
      expect(find.text('确认恢复'), findsNWidgets(2));
      expect(find.textContaining('最近云端检测'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('恢复选项'), findsOneWidget);
      await tap(tester, const Key('restore_section_settings'));
      await tap(tester, const Key('restore_preview'));
      expect(repository.previewSections, BackupArchive.sections);
      expect(repository.previewPreferArchive, isTrue);
      repository.setPrivacy(true);
      await tester.pumpAndSettle();
      expect(find.text('确认恢复'), findsNothing);
      expect(find.textContaining('秘密设备'), findsNothing);
      expect(find.text('隐私模式下不可查看或备份'), findsWidgets);
      expect(repository.restores, 0);
    },
  );

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('restore pages fit 320dp $brightness at ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository()
          ..localArchives = [_Local(archive('fit', all: true))];
        await _pump(tester, repository, brightness: brightness, scale: scale);
        await tap(tester, const Key('backup_local'));
        await tap(tester, const Key('local_fit'));
        await tap(tester, const Key('backup_restore'));
        expect(tester.takeException(), isNull);
        // Footer remains visible even when options must scroll.
        expect(
          find.byKey(const Key('restore_preview')).hitTestable(),
          findsOneWidget,
        );
        await tap(tester, const Key('restore_prefer_archive'));
        expect(
          find.byKey(const Key('restore_preview')).hitTestable(),
          findsOneWidget,
        );
        await tap(tester, const Key('restore_preview'));
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('restore_confirm')).hitTestable(),
          findsOneWidget,
        );
        await tap(tester, const Key('restore_confirm'));
        expect(repository.restores, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'HTTP configuration requires an explicit transport-risk checkbox',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      await tap(tester, const Key('backup_config'));
      await tester.enterText(
        find.byKey(const Key('webdav_endpoint')),
        'http://dav.example/',
      );
      await tap(tester, const Key('webdav_save'));
      expect(repository.configurations, 0);
      expect(find.textContaining('HTTP'), findsWidgets);
      await tap(tester, const Key('webdav_allow_http'));
      await tap(tester, const Key('webdav_save'));
      expect(repository.configurations, 1);
      expect(repository.config!.allowHttp, isTrue);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('320dp doubled text works in $brightness', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await _pump(tester, repository, brightness: brightness, scale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, const Key('backup_config'));
      expect(tester.takeException(), isNull);
    });
  }
}

final _config = WebDavConfig(
  endpoint: Uri.parse('https://dav.example/'),
  username: 'user',
);

class _Local implements LocalBackup {
  _Local(this.archive);
  @override
  final BackupArchive archive;
  @override
  String get fileName => archive.fileName;
  @override
  int get bytes => archive.encode().length;
}

class _Preview implements RestorePreview {
  _Preview(
    this.archive,
    this.before,
    this.groups,
    this.replace,
    this.preferArchive,
  );
  @override
  final BackupArchive archive;
  @override
  final Map<String, Map<String, Object?>> before, groups;
  @override
  final bool replace, preferArchive;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository extends ChangeNotifier implements BackupRepository {
  @override
  DateTime? get recentBackupAt => null;
  @override
  DateTime? recentCheckAt;
  @override
  WebDavConfig? config;
  @override
  String deviceName = '本机';
  @override
  bool autoCheck = false, busy = false, isPrivate = false;
  @override
  String? status, error;
  @override
  int pendingCloudCount = 0;
  @override
  List<LocalBackup> localArchives = [];
  @override
  final remoteEntries = [
    WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/XDownloader/Pixel%2011%20Pro_2026-11-01_00-00-00.000Z.zip',
      ),
      name: 'Pixel 11 Pro_2026-11-01_00-00-00.000Z.zip',
      modifiedAt: DateTime.utc(2026, 11, 1),
      bytes: 100,
    ),
    WebDavEntry(
      uri: Uri.parse(
        'https://dav.example/XDownloader/Pixel%2011%20Pro_2026-10-01_00-00-00.000Z.zip',
      ),
      name: 'Pixel 11 Pro_2026-10-01_00-00-00.000Z.zip',
      modifiedAt: DateTime.utc(2026, 10, 1),
      bytes: 100,
    ),
  ];
  final before = <String, Map<String, Object?>>{
    'favorites': {
      'items': [favorite()],
      'categories': [],
    },
  };
  int restores = 0, configurations = 0;
  BackupLocation? createdLocation;
  Set<String>? createdSections, previewSections;
  bool? previewReplace, previewPreferArchive;
  WebDavEntry? downloaded;

  void setPrivacy(bool value) {
    isPrivate = value;
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> refreshLocal() async {}
  @override
  Future<void> refreshRemote() async {}
  @override
  Future<void> configure({
    required WebDavConfig config,
    required String password,
    required String deviceName,
    required bool autoCheck,
  }) async {
    this.config = config;
    this.deviceName = deviceName;
    this.autoCheck = autoCheck;
    configurations++;
    notifyListeners();
  }

  @override
  Future<void> setAutoCheck(bool value) async {
    autoCheck = value;
    notifyListeners();
  }

  @override
  Future<BackupArchive> create({
    Set<String>? sections,
    BackupLocation location = BackupLocation.both,
  }) async {
    createdLocation = location;
    createdSections = sections;
    return archive('created');
  }

  @override
  Future<BackupArchive> download(WebDavEntry entry) async {
    downloaded = entry;
    return archive('downloaded');
  }

  @override
  Future<RestorePreview> preview(
    BackupArchive archive, {
    required bool replace,
    bool preferArchive = false,
    Set<String>? sections,
  }) async {
    previewSections = sections;
    previewReplace = replace;
    previewPreferArchive = preferArchive;
    return _Preview(
      archive,
      before,
      {for (final key in sections!) key: archive.data[key]!},
      replace,
      preferArchive,
    );
  }

  @override
  Future<void> restore(RestorePreview preview) async {
    restores++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

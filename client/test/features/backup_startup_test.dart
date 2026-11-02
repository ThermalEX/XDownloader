import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app_shell.dart';
import 'package:xdownloader/app/bootstrap.dart';
import 'package:xdownloader/data/repositories/backup_repository.dart';

import '../support/app_fixture.dart';

class _Backup extends ChangeNotifier implements BackupRepository {
  int checks = 0;
  final wait = Completer<void>();
  @override
  bool isPrivate = false;
  @override
  int pendingCloudCount = 0;
  @override
  Future<void> checkAtStartup() async {
    checks++;
    await wait.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final privacy in [false, true]) {
    testWidgets(
      'startup detection is nonblocking and privacy=$privacy gates prompt',
      (tester) async {
        final fixture = AppFixture();
        await fixture.initialize();
        final backup = _Backup()..isPrivate = privacy;
        final d = fixture.dependencies;
        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              dependencies: AppDependencies(
                downloads: d.downloads,
                sources: d.sources,
                settings: d.settings,
                favorites: d.favorites,
                shares: d.shares,
                parser: d.parser,
                updates: d.updates,
                readClipboard: d.readClipboard,
                backups: backup,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(backup.checks, 1);
        expect(find.text('XDownloader'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        backup.pendingCloudCount = 2;
        backup.wait.complete();
        await tester.pumpAndSettle();
        expect(find.text('发现云端存档'), privacy ? findsNothing : findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await fixture.close();
        backup.dispose();
      },
    );
  }
}

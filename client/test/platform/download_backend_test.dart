import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/platform/android_download_backend.dart';

void main() {
  test(
    'thumbnail cache is bounded and deletion invalidates the exact saved URI',
    () async {
      final calls = <String>[];
      final backend = AndroidDownloadBackend(
        call: (method, args) async {
          calls.add('$method:${args['locator']}');
          return method == 'thumbnail' ? Uint8List.fromList([1, 2, 3]) : null;
        },
      );
      const file = SavedFile(
        locator: 'content://media/external/downloads/123',
        displayName: 'test.mp4',
        bytes: 8,
        mimeType: 'video/mp4',
      );
      await backend.thumbnailSavedFile(file);
      await backend.thumbnailSavedFile(file);
      expect(calls.where((s) => s.startsWith('thumbnail')), hasLength(1));
      await backend.ensureReadable(file);
      await backend.deleteSavedFile(file);
      await backend.thumbnailSavedFile(file);
      expect(calls.where((s) => s.startsWith('thumbnail')), hasLength(2));
      for (var i = 0; i < 33; i++) {
        await backend.thumbnailSavedFile(
          SavedFile(
            locator: 'content://media/external/downloads/${1000 + i}',
            displayName: '$i.mp4',
            bytes: 8,
            mimeType: 'video/mp4',
          ),
        );
      }
      final before = calls.length;
      await backend.thumbnailSavedFile(file);
      expect(calls.length, before + 1);
      await backend.close();
    },
  );
  test(
    'file deletion sends its exact receipt and preserves native errors',
    () async {
      var failed = false;
      final backend = AndroidDownloadBackend(
        call: (method, args) async {
          expect(method, 'deleteSavedFile');
          expect(args['locator'], 'content://media/external/downloads/123');
          if (failed) {
            throw PlatformException(
              code: 'storage',
              message: 'Permission denied',
            );
          }
          return null;
        },
      );
      const file = SavedFile(
        locator: 'content://media/external/downloads/123',
        displayName: 'test.mp4',
        bytes: 8,
        mimeType: 'video/mp4',
      );
      await backend.deleteSavedFile(file);
      failed = true;
      await expectLater(
        backend.deleteSavedFile(file),
        throwsA(
          isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.storage),
        ),
      );
      await backend.close();
    },
  );
  test('storage publication errors remain recoverable transfers with request metadata', () async {
    final backend = AndroidDownloadBackend(
      call: (_, _) async => [
        {
          'taskId': 'a',
          'phase': 'failed',
          'bytes': 8,
          'canPublish': true,
          'error': 'Disk full',
          'request': {
            'taskId': 'a',
            'url': 'https://video.twimg.com/a.mp4',
            'displayName': 'a.mp4',
            'headers': <String, String>{},
            'mediaIndex': 1,
          },
        },
      ],
    );
    final state = (await backend.snapshot()).single;
    expect(state.phase, BackendPhase.transferred);
    expect(state.error?.kind, FailureKind.storage);
    expect(state.request?.taskId, 'a');
    await backend.close();
  });
  late Directory temp;
  late File staging;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('xdl-backend-');
    staging = await File('${temp.path}/a.mp4')
        .writeAsBytes([0, 0, 0, 24, 102, 116, 121, 112]);
  });
  tearDown(() async => temp.delete(recursive: true));

  test('failed publish preserves staging', () async {
    final backend = AndroidDownloadBackend(
      call: (method, args) async {
        throw PlatformException(code: 'storage', message: 'Disk full');
      },
    );
    await expectLater(backend.publish('a'), throwsA(isA<AppFailure>()));
    expect(await staging.exists(), isTrue);
  });
  test('publish is idempotent and coalesces concurrent callers', () async {
    var exports = 0;
    final backend = AndroidDownloadBackend(
      call: (method, args) async {
        expect(method, 'publish');
        exports++;
        final output = await staging.copy('${temp.path}/public.mp4');
        return {
          'locator': output.path,
          'displayName': 'a.mp4',
          'bytes': await output.length(),
          'mimeType': 'video/mp4',
        };
      },
    );
    final files = await Future.wait([
      backend.publish('a'),
      backend.publish('a'),
    ]);
    expect(files[0].locator, files[1].locator);
    expect((await backend.publish('a')).locator, files[0].locator);
    expect(exports, 1);
    expect(temp.listSync().whereType<File>().length, 2);
  });
  test('cancel only cleans up its own task', () async {
    final other = await File('${temp.path}/b.mp4').writeAsBytes([1]);
    final backend = AndroidDownloadBackend(
      call: (method, args) async {
        expect(args['taskId'], 'a');
        expect(method, 'cancel');
        await staging.delete();
        return null;
      },
    );
    await backend.cancel('a');
    expect(await staging.exists(), isFalse);
    expect(await other.exists(), isTrue);
  });
  test('invalid public receipts cannot report success', () async {
    for (final data in [
      {'locator': '', 'bytes': 8, 'mimeType': 'video/mp4'},
      {'locator': 'content://test/1', 'bytes': 0, 'mimeType': 'video/mp4'},
      {'locator': 'content://test/1', 'bytes': 8, 'mimeType': 'text/html'},
    ]) {
      final backend = AndroidDownloadBackend(
        call: (_, _) async => {'displayName': 'a.mp4', ...data},
      );
      await expectLater(backend.publish('a'), throwsA(isA<AppFailure>()));
    }
  });
}

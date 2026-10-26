import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/models/app_failure.dart';
import 'package:xdownloader/core/models/download.dart';
import 'package:xdownloader/core/models/media.dart';
import 'package:xdownloader/core/parsing/parse_client.dart';
import 'package:xdownloader/core/parsing/post_link.dart';
import 'package:xdownloader/data/repositories/download_retry_resolver.dart';

final original = DownloadRequest(
  taskId: 'old',
  url: Uri.parse('https://video.example/expired.mp4'),
  displayName: 'my-original-name.mp4',
  headers: const {'referer': 'https://x.com/'},
  mediaIndex: 2,
  postUrl: Uri.parse('https://x.com/author/status/123456'),
  coverUrl: Uri.parse('https://image.example/original.jpg'),
  width: 1280,
  height: 720,
);

MediaVariant variant(int index, int width, int height, String path) =>
    MediaVariant(
      index,
      width,
      height,
      Uri.parse('https://video.example/$path.mp4'),
      1000,
      'mp4',
    );

MediaResult result(List<MediaItem> items, {String id = '123456'}) =>
    MediaResult(
      PostLink(id, 'author', Uri.parse('https://x.com/author/status/$id')),
      'new title',
      'author',
      null,
      null,
      items,
      'test',
    );

void main() {
  test(
    'refresh chooses original media and exact quality while retaining names',
    () async {
      final resolver = DownloadRetryResolver(
        parsePost: (input, cancellation) async {
          expect(input, 'https://x.com/author/status/123456');
          return result([
            MediaItem(1, [variant(1, 1280, 720, 'wrong-media')]),
            MediaItem(2, [
              variant(2, 1920, 1080, 'larger'),
              variant(2, 1280, 720, 'exact'),
              variant(2, 640, 360, 'smaller'),
            ]),
          ]);
        },
      );
      final fresh = await resolver.call(original, ParseCancellation());
      expect(fresh.url.toString(), 'https://video.example/exact.mp4');
      expect(fresh.displayName, 'my-original-name.mp4');
      expect(fresh.postUrl, original.postUrl);
      expect(fresh.coverUrl, original.coverUrl);
      expect(fresh.headers, original.headers);
      expect(fresh.mediaIndex, 2);
    },
  );

  test('missing exact quality chooses nearest non-upgrade', () async {
    final resolver = DownloadRetryResolver(
      parsePost: (_, _) async => result([
        MediaItem(2, [
          variant(2, 1920, 1080, 'larger'),
          variant(2, 960, 540, 'nearest'),
          variant(2, 640, 360, 'smallest'),
        ]),
      ]),
    );
    final fresh = await resolver.call(original, ParseCancellation());
    expect(fresh.url.toString(), 'https://video.example/nearest.mp4');
    expect(fresh.width, 960);
    expect(fresh.height, 540);
  });

  test('only higher quality remains uses the nearest higher variant', () async {
    final resolver = DownloadRetryResolver(
      parsePost: (_, _) async => result([
        MediaItem(2, [
          variant(2, 3840, 2160, 'huge'),
          variant(2, 1920, 1080, 'nearest-higher'),
        ]),
      ]),
    );
    final fresh = await resolver.call(original, ParseCancellation());
    expect(fresh.url.toString(), 'https://video.example/nearest-higher.mp4');
  });

  for (final scenario in ['missing-media', 'wrong-post', 'unsafe-url']) {
    test(
      '$scenario refuses refresh instead of downloading different media',
      () async {
        final resolver = DownloadRetryResolver(
          parsePost: (_, _) async => result([
            MediaItem(scenario == 'missing-media' ? 1 : 2, [
              scenario == 'unsafe-url'
                  ? MediaVariant(
                      2,
                      1280,
                      720,
                      Uri.parse('file:///unsafe.mp4'),
                      1000,
                      'mp4',
                    )
                  : variant(
                      scenario == 'missing-media' ? 1 : 2,
                      1280,
                      720,
                      'different',
                    ),
            ]),
          ], id: scenario == 'wrong-post' ? '654321' : '123456'),
        );
        await expectLater(
          resolver.call(original, ParseCancellation()),
          throwsA(isA<AppFailure>()),
        );
      },
    );
  }

  test('late parser result is rejected after cancellation', () async {
    final cancellation = ParseCancellation();
    final resolver = DownloadRetryResolver(
      parsePost: (_, _) async {
        cancellation.cancel();
        return result([
          MediaItem(2, [variant(2, 1280, 720, 'fresh')]),
        ]);
      },
    );
    await expectLater(
      resolver.call(original, cancellation),
      throwsA(
        isA<AppFailure>().having((e) => e.kind, 'kind', FailureKind.cancelled),
      ),
    );
  });
}

import '../../core/models/app_failure.dart';
import '../../core/models/download.dart';
import '../../core/models/media.dart';
import '../../core/parsing/parse_client.dart';
import '../../core/parsing/post_link.dart';

/// Refreshes only the selected video; a different video is never a substitute.
class DownloadRetryResolver {
  DownloadRetryResolver({required this.parsePost});

  final Future<MediaResult> Function(String, ParseCancellation) parsePost;

  Future<DownloadRequest> call(
    DownloadRequest request,
    ParseCancellation cancellation,
  ) async {
    _checkCancelled(cancellation);
    final post = PostLink.tryParse(request.postUrl?.toString() ?? '');
    if (post == null) {
      throw const AppFailure(FailureKind.invalidLink, '没有可重新解析的原帖子链接');
    }
    final result = await parsePost(post.canonicalUrl.toString(), cancellation);
    _checkCancelled(cancellation);
    if (result.post.postId != post.postId) {
      throw const AppFailure(FailureKind.noVideo, '解析结果与原帖子不一致，请重新解析');
    }
    final variants = result.items
        .where((item) => item.index == request.mediaIndex)
        .expand((item) => item.variants)
        .where(
          (variant) =>
              variant.mediaIndex == request.mediaIndex &&
              ['https', 'http'].contains(variant.url.scheme) &&
              variant.url.host.isNotEmpty &&
              variant.url.userInfo.isEmpty &&
              variant.extension.toLowerCase() == 'mp4' &&
              variant.url.path.toLowerCase().endsWith('.mp4'),
        )
        .toList();
    if (variants.isEmpty) {
      throw const AppFailure(FailureKind.noVideo, '原视频已不可用，请打开原帖子重新选择');
    }
    final variant = _closest(variants, request);
    return DownloadRequest(
      taskId: request.taskId,
      url: variant.url,
      displayName: request.displayName,
      headers: request.headers,
      mediaIndex: request.mediaIndex,
      postUrl: request.postUrl,
      coverUrl: request.coverUrl,
      width: variant.width > 0 ? variant.width : null,
      height: variant.height > 0 ? variant.height : null,
    );
  }

  static MediaVariant _closest(
    List<MediaVariant> variants,
    DownloadRequest request,
  ) {
    final width = request.width ?? 0;
    final height = request.height ?? 0;
    if (width <= 0 || height <= 0) {
      variants.sort(compareVariants);
      return variants.first;
    }
    final exact =
        variants.where((v) => v.width == width && v.height == height).toList()
          ..sort(compareVariants);
    if (exact.isNotEmpty) return exact.first;
    int shortSide(MediaVariant v) => v.width < v.height ? v.width : v.height;
    final originalShort = width < height ? width : height;
    final originalArea = width * height;
    final measured = variants
        .where((v) => v.width > 0 && v.height > 0)
        .toList();
    if (measured.isEmpty) return variants.first;
    final nonUpgrade = measured
        .where(
          (v) =>
              shortSide(v) <= originalShort &&
              v.width * v.height <= originalArea,
        )
        .toList();
    final candidates = nonUpgrade.isEmpty ? measured : nonUpgrade;
    candidates.sort((a, b) {
      final side = (shortSide(a) - originalShort).abs().compareTo(
        (shortSide(b) - originalShort).abs(),
      );
      if (side != 0) return side;
      final area = (a.width * a.height - originalArea).abs().compareTo(
        (b.width * b.height - originalArea).abs(),
      );
      return area != 0 ? area : compareVariants(a, b);
    });
    return candidates.first;
  }

  static void _checkCancelled(ParseCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const AppFailure(FailureKind.cancelled, '已取消重新解析');
    }
  }
}

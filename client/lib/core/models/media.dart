import '../parsing/post_link.dart';

class MediaVariant {
  const MediaVariant(
    this.mediaIndex,
    this.width,
    this.height,
    this.url,
    this.bitrate,
    this.extension,
  );
  final int mediaIndex, width, height, bitrate;
  final Uri url;
  final String extension;
}

class MediaItem {
  MediaItem(this.index, List<MediaVariant> variants)
    : variants = List<MediaVariant>.unmodifiable(
        <MediaVariant>[...variants]..sort(compareVariants),
      );
  final int index;
  final List<MediaVariant> variants;
}

int compareVariants(MediaVariant a, MediaVariant b) {
  int shortSide(MediaVariant v) => v.width < v.height ? v.width : v.height;
  final pixels = shortSide(b).compareTo(shortSide(a));
  if (pixels != 0) return pixels;
  final area = (b.width * b.height).compareTo(a.width * a.height);
  return area == 0 ? b.bitrate.compareTo(a.bitrate) : area;
}

class MediaResult {
  MediaResult(
    this.post,
    this.title,
    this.author,
    this.thumbnail,
    this.duration,
    List<MediaItem> items,
    this.sourceId,
  ) : items = List.unmodifiable(items);
  final PostLink post;
  final String title, author, sourceId;
  final Uri? thumbnail;
  final Duration? duration;
  final List<MediaItem> items;
}

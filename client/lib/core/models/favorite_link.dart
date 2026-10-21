import '../parsing/post_link.dart';

class FavoriteLink {
  const FavoriteLink({
    required this.postId,
    required this.url,
    required this.title,
    required this.createdAt,
  });
  final String postId, title;
  final Uri url;
  final DateTime createdAt;
  Map<String, Object?> toJson() => {
    'postId': postId,
    'url': url.toString(),
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
  factory FavoriteLink.fromJson(Map<String, Object?> data) {
    final raw = data['url'] as String;
    final post = PostLink.tryParse(raw);
    if (post == null ||
        raw != post.canonicalUrl.toString() ||
        post.postId != data['postId']) {
      throw const FormatException('Invalid favorite link');
    }
    return FavoriteLink(
      postId: post.postId,
      url: post.canonicalUrl,
      title: data['title'] as String,
      createdAt: DateTime.parse(data['createdAt'] as String),
    );
  }
}

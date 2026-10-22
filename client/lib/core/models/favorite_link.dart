import '../parsing/post_link.dart';

class FavoriteLink {
  const FavoriteLink({
    required this.postId,
    required this.url,
    required this.title,
    required this.createdAt,
    this.category = '',
  });
  final String postId, title, category;
  final Uri url;
  final DateTime createdAt;
  FavoriteLink copyWith({String? title, String? category}) => FavoriteLink(
    postId: postId,
    url: url,
    title: title ?? this.title,
    category: category ?? this.category,
    createdAt: createdAt,
  );
  Map<String, Object?> toJson() => {
    'postId': postId,
    'url': url.toString(),
    'title': title,
    'category': category,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
  factory FavoriteLink.fromJson(Map<String, Object?> data) {
    final raw = data['url'] as String;
    final post = PostLink.tryParse(raw);
    final category = data['category'] as String? ?? '';
    if (category.runes.length > 40) {
      throw const FormatException('Invalid favorite category');
    }
    if (post == null ||
        raw != post.canonicalUrl.toString() ||
        post.postId != data['postId']) {
      throw const FormatException('Invalid favorite link');
    }
    return FavoriteLink(
      postId: post.postId,
      url: post.canonicalUrl,
      title: data['title'] as String,
      category: category,
      createdAt: DateTime.parse(data['createdAt'] as String),
    );
  }
}

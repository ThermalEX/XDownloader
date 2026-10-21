class PostLink {
  const PostLink(this.postId, this.user, this.canonicalUrl);
  final String postId, user;
  final Uri canonicalUrl;
  static final _link = RegExp(
    r'(?<![A-Za-z0-9_./:@-])(?:https?://)?(?:www\.|mobile\.|m\.)?(?:x|twitter)\.com/(?:(?<user>[A-Za-z0-9_]{1,25})/)?(?:i/web/|i/)?status(?:es)?/(?<id>[0-9]{5,25})(?![A-Za-z0-9_])',
    caseSensitive: false,
  );
  static PostLink? tryParse(String text) {
    final match = _link.firstMatch(text);
    if (match == null) return null;
    final id = match.namedGroup('id')!;
    final user = match.namedGroup('user') ?? 'i';
    return PostLink(id, user, Uri.https('x.com', '/$user/status/$id'));
  }
}

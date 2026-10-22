import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../app/app_shell.dart';

/// Shared theme-aware rendering for bundled and downloaded release notes.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.data, required this.onOpenLink});
  final String data;
  final Future<void> Function(Uri) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        h1: theme.textTheme.headlineSmall,
        h2: theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // Notes never fetch remote images or read paths supplied by a release.
      imageBuilder: (_, _, _) => const SizedBox.shrink(),
      onTapLink: (_, href, _) {
        final uri = Uri.tryParse(href ?? '');
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return;
        }
        runAction(context, () => onOpenLink(uri));
      },
    );
  }
}

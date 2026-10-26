import 'package:flutter/material.dart';

import 'handed_layout.dart';

import '../data/repositories/settings_repository.dart';
import '../core/parsing/post_link.dart';

/// Page-local search; query data never leaves the device or enters snapshots.
class LibrarySearch extends ChangeNotifier {
  LibrarySearch(this.settings, {this.onChanged}) {
    settings.addListener(_privacyChanged);
  }

  final SettingsRepository settings;
  final VoidCallback? onChanged;
  final text = TextEditingController();
  List<String> _terms = const [];
  bool get isEmpty => _terms.isEmpty;

  void update(String value) {
    onChanged?.call();
    final trimmed = value.trim();
    final link =
        trimmed.startsWith('https://') && !trimmed.contains(RegExp(r'\s'))
        ? PostLink.tryParse(trimmed)
        : null;
    _terms = (link?.postId ?? value)
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    notifyListeners();
  }

  bool matches(Iterable<Object?> fields) {
    if (isEmpty) return true;
    final haystack = fields.whereType<Object>().join(' ').toLowerCase();
    return _terms.every(haystack.contains);
  }

  void clear() {
    if (text.text.isEmpty && isEmpty) return;
    text.clear();
    update('');
  }

  void _privacyChanged() {
    if (settings.value.privacyMode) clear();
  }

  @override
  void dispose() {
    settings.removeListener(_privacyChanged);
    text.dispose();
    super.dispose();
  }
}

class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.search,
    required this.name,
  });
  final LibrarySearch search;
  final String name;

  @override
  Widget build(BuildContext context) {
    final clear = search.text.text.isEmpty
        ? null
        : IconButton(
            tooltip: '清空搜索',
            onPressed: search.clear,
            icon: const Icon(Icons.close),
          );
    final left = HandedLayout.isLeft(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TextField(
        key: Key('${name}_search'),
        controller: search.text,
        onChanged: search.update,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          hintText: '搜索标题、链接或帖子编号',
          prefixIcon: left ? clear : const Icon(Icons.search),
          suffixIcon: left ? const Icon(Icons.search) : clear,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainer,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

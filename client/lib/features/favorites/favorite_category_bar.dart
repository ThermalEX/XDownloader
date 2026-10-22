import 'package:flutter/material.dart';

String categoryLabel(String category) => switch (category) {
  '' => '未分类',
  '全部' || '未分类' => '$category（分类）',
  _ => category,
};

class FavoriteCategoryBar extends StatefulWidget {
  const FavoriteCategoryBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.onManage,
  });
  final List<String> categories;
  final Set<String> selected;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String>? onManage;
  @override
  State<FavoriteCategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<FavoriteCategoryBar> {
  final _scroll = ScrollController();
  bool _fade = false;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final fade = _scroll.position.extentAfter > 1;
    if (fade != _fade) setState(() => _fade = fade);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
          return false;
        },
        child: ShaderMask(
          key: const Key('favorite_categories_fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [Colors.white, _fade ? Colors.transparent : Colors.white],
            stops: [rect.width <= 24 ? 0 : 1 - 24 / rect.width, 1],
          ).createShader(rect),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final category in <String?>[
                  null,
                  '',
                  ...widget.categories,
                ])
                  Padding(
                    key: ValueKey(category),
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress:
                          category == null ||
                              category.isEmpty ||
                              widget.onManage == null
                          ? null
                          : () => widget.onManage!(category),
                      child: FilterChip(
                        key: category == null
                            ? const Key('favorite_category_all')
                            : Key('favorite_category:$category'),
                        label: Text(
                          category == null ? '全部' : categoryLabel(category),
                        ),
                        selected: category == null
                            ? widget.selected.isEmpty
                            : widget.selected.contains(category),
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: (_) => widget.onSelected(category),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

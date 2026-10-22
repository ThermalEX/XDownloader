import 'package:flutter/foundation.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/favorite_link.dart';
import '../../core/parsing/post_link.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

enum FavoriteSort { newest, oldest, title }

class FavoriteRepository extends ChangeNotifier {
  FavoriteRepository(this.store);
  final SnapshotStore store;
  final _queue = SerialQueue();
  List<FavoriteLink> _items = [];
  FavoriteSort _sort = FavoriteSort.newest;
  FavoriteSort get sort => _sort;
  List<String> get categories =>
      (_items.map((f) => f.category).where((c) => c.isNotEmpty).toSet().toList()
        ..sort());
  List<FavoriteLink> get items {
    final positions = {
      for (var i = 0; i < _items.length; i++) _items[i].postId: i,
    };
    final result = [..._items]
      ..sort((a, b) {
        final order = switch (_sort) {
          FavoriteSort.newest => b.createdAt.compareTo(a.createdAt),
          FavoriteSort.oldest => a.createdAt.compareTo(b.createdAt),
          FavoriteSort.title => a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          ),
        };
        return order != 0
            ? order
            : positions[a.postId]!.compareTo(positions[b.postId]!);
      });
    return List.unmodifiable(result);
  }

  Future<void> initialize() async {
    final data = await store.read('favorites');
    try {
      final items = (data['items'] as List? ?? [])
          .map(
            (raw) =>
                FavoriteLink.fromJson(Map<String, Object?>.from(raw as Map)),
          )
          .toList();
      if (items.map((f) => f.postId).toSet().length != items.length) {
        throw const FormatException('Duplicate favorite');
      }
      _items = items;
      _sort = FavoriteSort.values.byName(data['sort'] as String? ?? 'newest');
    } catch (_) {
      throw const AppFailure(FailureKind.storage, '收藏数据损坏，原文件已保留');
    }
  }

  Future<void> _save(List<FavoriteLink> next, {FavoriteSort? sort}) async {
    await store.write('favorites', {
      'items': next.map((f) => f.toJson()).toList(),
      'sort': (sort ?? _sort).name,
    });
    _items = next;
    _sort = sort ?? _sort;
    notifyListeners();
  }

  Future<void> setSort(FavoriteSort value) =>
      _queue.run(() => _save(_items, sort: value));
  Future<void> update(
    String postId, {
    required String title,
    required String category,
  }) => _queue.run(() async {
    final name = title.trim(), group = category.trim();
    if (name.isEmpty || name.runes.length > 300 || group.runes.length > 40) {
      throw const AppFailure(FailureKind.malformed, '名称需为 1–300 字，分类最多 40 字');
    }
    await _save(
      _items
          .map(
            (f) => f.postId == postId
                ? f.copyWith(title: name, category: group)
                : f,
          )
          .toList(),
    );
  });

  Future<bool> add(String input, {String? title}) => _queue.run(() async {
    final post = PostLink.tryParse(input);
    if (post == null) {
      throw const AppFailure(FailureKind.invalidLink, '请输入有效的 X 帖子链接');
    }
    final text = String.fromCharCodes((title ?? '').trim().runes.take(300));
    final existing = _items.where((f) => f.postId == post.postId).firstOrNull;
    if (existing != null) {
      if (existing.title.isEmpty && text.isNotEmpty) {
        await _save(
          _items
              .map((f) => f.postId == post.postId ? f.copyWith(title: text) : f)
              .toList(),
        );
      }
      return false;
    }
    await _save([
      FavoriteLink(
        postId: post.postId,
        url: post.canonicalUrl,
        title: text,
        createdAt: DateTime.now().toUtc(),
      ),
      ..._items,
    ]);
    return true;
  });
  Future<void> remove(String postId) => _queue.run(() async {
    if (_items.any((f) => f.postId == postId)) {
      await _save(_items.where((f) => f.postId != postId).toList());
    }
  });
}

import 'package:flutter/foundation.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/favorite_link.dart';
import '../../core/parsing/post_link.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

enum FavoriteSort { defaultOrder, newest, oldest, title }

class FavoriteRemoval {
  const FavoriteRemoval._(
    this.item,
    this.position,
    this.previousId,
    this.nextId,
  );
  final FavoriteLink item;
  final int position;
  final String? previousId, nextId;
}

class FavoriteRepository extends ChangeNotifier {
  FavoriteRepository(this.store);
  final SnapshotStore store;
  final _queue = SerialQueue();
  List<FavoriteLink> _items = [];
  List<String> _categories = [];
  FavoriteSort _sort = FavoriteSort.defaultOrder;
  List<FavoriteLink>? _snapshot;
  FavoriteSort get sort => _sort;
  List<String> get categories => List.unmodifiable(_categories);
  List<FavoriteLink> get items => _snapshot ??= _sortedItems();
  List<FavoriteLink> _sortedItems() {
    if (_sort == FavoriteSort.defaultOrder) return List.unmodifiable(_items);
    final positions = {
      for (var i = 0; i < _items.length; i++) _items[i].postId: i,
    };
    final titles = _sort == FavoriteSort.title
        ? {for (final item in _items) item.postId: item.title.toLowerCase()}
        : const <String, String>{};
    final result = [..._items]
      ..sort((a, b) {
        final order = switch (_sort) {
          FavoriteSort.defaultOrder => 0,
          FavoriteSort.newest => b.createdAt.compareTo(a.createdAt),
          FavoriteSort.oldest => a.createdAt.compareTo(b.createdAt),
          FavoriteSort.title => titles[a.postId]!.compareTo(titles[b.postId]!),
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
      final declared = (data['categories'] as List? ?? []).cast<String>();
      if (declared.any((c) => c.trim().isEmpty || c.runes.length > 40) ||
          declared.toSet().length != declared.length) {
        throw const FormatException('Invalid categories');
      }
      final used =
          items
              .map((f) => f.category)
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      _categories = {...declared, ...used}.toList();
      _sort = FavoriteSort.values.byName(
        data['sort'] as String? ?? 'defaultOrder',
      );
      _snapshot = null;
    } catch (_) {
      throw const AppFailure(FailureKind.storage, '收藏数据损坏，原文件已保留');
    }
  }

  Future<void> _save(
    List<FavoriteLink> next, {
    FavoriteSort? sort,
    List<String>? categories,
  }) async {
    final groups = {
      ...(categories ?? _categories),
      ...next.map((f) => f.category).where((c) => c.isNotEmpty),
    }.toList();
    await store.write('favorites', {
      'items': next.map((f) => f.toJson()).toList(),
      'sort': (sort ?? _sort).name,
      'categories': groups,
    });
    _items = next;
    _categories = groups;
    _sort = sort ?? _sort;
    _snapshot = null;
    notifyListeners();
  }

  Future<void> setSort(FavoriteSort value) =>
      _queue.run(() => _save(_items, sort: value));
  Future<bool> addCategory(String input) => _queue.run(() async {
    final name = input.trim();
    if (name.isEmpty || name.runes.length > 40) {
      throw const AppFailure(FailureKind.malformed, '分类名称需为 1–40 字');
    }
    if (_categories.contains(name)) return false;
    await _save(_items, categories: [..._categories, name]);
    return true;
  });
  Future<void> renameCategory(String previous, String input) => _queue.run(
    () async {
      final name = input.trim();
      if (name.isEmpty ||
          name.runes.length > 40 ||
          !_categories.contains(previous)) {
        throw const AppFailure(FailureKind.malformed, '分类名称需为1–40字，原分类必须存在');
      }
      if (name == previous) return;
      if (_categories.contains(name)) {
        throw const AppFailure(FailureKind.malformed, '该分类已存在');
      }
      await _save(
        _items
            .map((f) => f.category == previous ? f.copyWith(category: name) : f)
            .toList(),
        categories: _categories.map((c) => c == previous ? name : c).toList(),
      );
    },
  );
  Future<void> deleteCategory(String name) => _queue.run(() async {
    if (!_categories.contains(name)) return;
    await _save(
      _items
          .map((f) => f.category == name ? f.copyWith(category: '') : f)
          .toList(),
      categories: _categories.where((c) => c != name).toList(),
    );
  });
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

  Future<bool> add(
    String input, {
    String? title,
    String? author,
    Uri? coverUrl,
  }) => _queue.run(() async {
    final post = PostLink.tryParse(input);
    if (post == null) {
      throw const AppFailure(FailureKind.invalidLink, '请输入有效的 X 帖子链接');
    }
    final text = String.fromCharCodes((title ?? '').trim().runes.take(300));
    final authorName = String.fromCharCodes(
      (author ?? '').trim().runes.take(300),
    );
    final existing = _items.where((f) => f.postId == post.postId).firstOrNull;
    if (existing != null) {
      if ((existing.title.isEmpty && text.isNotEmpty) ||
          (coverUrl != null && coverUrl != existing.coverUrl) ||
          (authorName.isNotEmpty && authorName != existing.author)) {
        await _save(
          _items
              .map(
                (f) => f.postId == post.postId
                    ? f.copyWith(
                        title: existing.title.isEmpty ? text : null,
                        coverUrl: coverUrl,
                        author: authorName.isEmpty ? null : authorName,
                      )
                    : f,
              )
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
        coverUrl: coverUrl,
        author: authorName.isEmpty ? null : authorName,
      ),
      ..._items,
    ]);
    return true;
  });
  Future<void> rememberCover(String postId, Uri? url) =>
      rememberMetadata(postId, coverUrl: url);

  Future<void> rememberMetadata(
    String postId, {
    Uri? coverUrl,
    String? author,
  }) => _queue.run(() async {
    final authorName = String.fromCharCodes(
      (author ?? '').trim().runes.take(300),
    );
    if (!_items.any(
      (f) =>
          f.postId == postId &&
          ((coverUrl != null && f.coverUrl != coverUrl) ||
              (authorName.isNotEmpty && f.author != authorName)),
    )) {
      return;
    }
    await _save(
      _items
          .map(
            (f) => f.postId == postId
                ? f.copyWith(
                    coverUrl: coverUrl,
                    author: authorName.isEmpty ? null : authorName,
                  )
                : f,
          )
          .toList(),
    );
  });
  Future<void> remove(String postId) async {
    await removeForUndo(postId);
  }

  Future<FavoriteRemoval?> removeForUndo(String postId) => _queue.run(() async {
    final index = _items.indexWhere((f) => f.postId == postId);
    if (index < 0) return null;
    final removed = FavoriteRemoval._(
      _items[index],
      index,
      index > 0 ? _items[index - 1].postId : null,
      index + 1 < _items.length ? _items[index + 1].postId : null,
    );
    await _save(_items.where((f) => f.postId != postId).toList());
    return removed;
  });
  Future<void> restore(FavoriteRemoval removed) => _queue.run(() async {
    if (_items.any((f) => f.postId == removed.item.postId)) return;
    final previous = _items.indexWhere((f) => f.postId == removed.previousId);
    final next = _items.indexWhere((f) => f.postId == removed.nextId);
    final position = previous >= 0
        ? previous + 1
        : next >= 0
        ? next
        : removed.position.clamp(0, _items.length);
    final category = _categories.contains(removed.item.category)
        ? removed.item.category
        : '';
    await _save(
      [..._items]..insert(position, removed.item.copyWith(category: category)),
    );
  });
  Future<List<FavoriteRemoval>> removeManyForUndo(Set<String> ids) =>
      _queue.run(() async {
        final removed = <FavoriteRemoval>[];
        for (var i = 0; i < _items.length; i++) {
          if (!ids.contains(_items[i].postId)) continue;
          removed.add(
            FavoriteRemoval._(
              _items[i],
              i,
              i > 0 ? _items[i - 1].postId : null,
              i + 1 < _items.length ? _items[i + 1].postId : null,
            ),
          );
        }
        if (removed.isNotEmpty) {
          await _save(_items.where((f) => !ids.contains(f.postId)).toList());
        }
        return removed;
      });
  Future<void> restoreMany(List<FavoriteRemoval> removed) =>
      _queue.run(() async {
        final next = [..._items];
        for (final entry in removed.reversed) {
          if (next.any((f) => f.postId == entry.item.postId)) continue;
          final previous = next.indexWhere((f) => f.postId == entry.previousId);
          final following = next.indexWhere((f) => f.postId == entry.nextId);
          final at = previous >= 0
              ? previous + 1
              : following >= 0
              ? following
              : entry.position.clamp(0, next.length);
          final category = _categories.contains(entry.item.category)
              ? entry.item.category
              : '';
          next.insert(at, entry.item.copyWith(category: category));
        }
        await _save(next);
      });
}

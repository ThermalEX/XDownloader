import 'package:flutter/foundation.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/favorite_link.dart';
import '../../core/parsing/post_link.dart';
import '../storage/snapshot_store.dart';
import '../storage/serial_queue.dart';

class FavoriteRepository extends ChangeNotifier {
  FavoriteRepository(this.store);
  final SnapshotStore store;
  final _queue = SerialQueue();
  List<FavoriteLink> _items = [];
  List<FavoriteLink> get items => List.unmodifiable(_items);

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
    } catch (_) {
      throw const AppFailure(FailureKind.storage, '收藏数据损坏，原文件已保留');
    }
  }

  Future<void> _save(List<FavoriteLink> next) async {
    await store.write('favorites', {
      'items': next.map((f) => f.toJson()).toList(),
    });
    _items = next;
    notifyListeners();
  }

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
              .map(
                (f) => f.postId == post.postId
                    ? FavoriteLink(
                        postId: f.postId,
                        url: f.url,
                        title: text,
                        createdAt: f.createdAt,
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

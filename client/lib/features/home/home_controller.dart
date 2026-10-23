import 'package:flutter/foundation.dart';

import 'dart:async';

import '../../app/bootstrap.dart';
import '../../core/models/app_failure.dart';
import '../../core/models/media.dart';
import '../../core/models/download.dart';
import '../../core/parsing/parse_client.dart';
import '../../core/parsing/post_link.dart';
import '../../core/naming/file_naming.dart';
import '../../platform/download_backend.dart';

class HomeController extends ChangeNotifier {
  HomeController(this.dependencies)
    : _privacyMode = dependencies.settings.value.privacyMode {
    dependencies.settings.addListener(_privacyChanged);
  }
  final AppDependencies dependencies;
  String input = '';
  MediaResult? result;
  bool busy = false;
  AppFailure? error;
  int _generation = 0;
  bool _disposed = false, _visible = true;
  String? _lastClipboard;
  ParseCancellation? _cancellation;
  bool _privacyMode;
  void _privacyChanged() {
    final enabled = dependencies.settings.value.privacyMode;
    if (enabled && !_privacyMode) clear();
    _privacyMode = enabled;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setInput(String value) {
    if (_disposed) return;
    cancelParse();
    input = value;
    result = null;
    error = null;
    _notify();
  }

  void setVisible(bool visible) {
    _visible = visible;
    if (!visible) cancelParse();
  }

  Future<void> parse(String text) async {
    if (_disposed) return;
    _cancellation?.cancel();
    final generation = ++_generation;
    final cancellation = _cancellation = ParseCancellation();
    input = text;
    busy = true;
    result = null;
    error = null;
    _notify();
    try {
      final value = await dependencies.parser.parse(
        text,
        sources: dependencies.sources.parseOrder,
        autoFallback: dependencies.sources.autoFallback,
        cancellation: cancellation,
      );
      if (!_disposed && generation == _generation) {
        result = value;
        if (!dependencies.settings.value.privacyMode) {
          // Metadata only; viewing favorites loads the actual cover lazily.
          unawaited(
            dependencies.favorites
                .rememberMetadata(
                  value.post.postId,
                  coverUrl: value.thumbnail,
                  author: value.author,
                )
                .catchError((_) {}),
          );
        }
      }
    } catch (e) {
      if (!_disposed &&
          generation == _generation &&
          !cancellation.isCancelled) {
        error = e is AppFailure
            ? e
            : AppFailure(FailureKind.network, '解析失败，请重试', '$e');
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> acceptSharedText(String text) => parse(text);
  Future<void> onResumed() async {
    if (_disposed ||
        !_visible ||
        !dependencies.settings.value.autoClipboard ||
        input.isNotEmpty) {
      return;
    }
    final generation = _generation;
    final text = await dependencies.readClipboard();
    if (_disposed ||
        !_visible ||
        generation != _generation ||
        input.isNotEmpty ||
        text == null) {
      return;
    }
    final canonical = PostLink.tryParse(text)?.canonicalUrl.toString();
    if (canonical == null || canonical == _lastClipboard) return;
    _lastClipboard = canonical;
    await parse(text);
  }

  Future<void> paste() async {
    if (_disposed || !_visible) {
      return;
    }
    final generation = _generation;
    final text = await dependencies.readClipboard();
    if (_disposed || !_visible || generation != _generation) return;
    if (text == null || PostLink.tryParse(text) == null) {
      throw const AppFailure(FailureKind.invalidLink, '剪贴板中没有有效的 X 帖子链接');
    }
    await parse(text);
  }

  Future<void> download(MediaVariant variant) async {
    final media = result;
    if (media == null) return;
    await dependencies.prepareDownload();
    final id = await dependencies.downloads.start(
      DownloadRequest(
        taskId: newTaskId(),
        url: variant.url,
        displayName: FileNaming.build(
          media,
          variant,
          template: dependencies.settings.value.fileNameTemplate,
          useOriginalName: dependencies.settings.value.useOriginalFileName,
        ),
        headers: const {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://x.com/',
        },
        mediaIndex: variant.mediaIndex,
        postUrl: media.post.canonicalUrl,
        coverUrl: media.thumbnail,
        width: variant.width,
        height: variant.height,
      ),
    );
    final record = dependencies.downloads.records
        .where((r) => r.taskId == id)
        .first;
    if (record.error != null) throw record.error!;
  }

  void clear() {
    _lastClipboard =
        PostLink.tryParse(input)?.canonicalUrl.toString() ?? _lastClipboard;
    cancelParse();
    input = '';
    result = null;
    error = null;
    _notify();
  }

  void cancelParse() {
    ++_generation;
    _cancellation?.cancel();
    busy = false;
    _notify();
  }

  @override
  void dispose() {
    dependencies.settings.removeListener(_privacyChanged);
    _disposed = true;
    ++_generation;
    _cancellation?.cancel();
    super.dispose();
  }
}

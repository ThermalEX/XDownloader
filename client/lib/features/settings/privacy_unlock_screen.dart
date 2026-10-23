import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/branding_assets.dart';
import '../../data/repositories/settings_repository.dart';

/// App-local PIN verification, presented independently of the settings form.
class PrivacyUnlockScreen extends StatefulWidget {
  const PrivacyUnlockScreen({super.key, required this.settings});
  final SettingsRepository settings;

  @override
  State<PrivacyUnlockScreen> createState() => _PrivacyUnlockScreenState();
}

class _PrivacyUnlockScreenState extends State<PrivacyUnlockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false, _committing = false;
  int _revision = 0;

  void _invalidate() {
    _revision++;
  }

  void _cancel() {
    if (_committing) return;
    _invalidate();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _invalidate();
    super.dispose();
  }

  void _edit(String value) {
    if (_committing) return;
    _revision++;
    setState(() {
      _pin = value;
      _error = null;
    });
  }

  void _digit(int digit) {
    if (_committing || _pin.length == 6) return;
    HapticFeedback.selectionClick();
    _edit('$_pin$digit');
  }

  Future<void> _check() async {
    if (!mounted ||
        _checking ||
        _pin.length < 4 ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    setState(() => _checking = true);
    final revision = _revision, candidate = _pin;
    try {
      final unlocked = await widget.settings.tryUnlockPrivacy(
        candidate,
        canCommit: () {
          if (!mounted ||
              revision != _revision ||
              ModalRoute.of(context)?.isCurrent != true) {
            return false;
          }
          setState(() => _committing = true);
          return true;
        },
      );
      if (unlocked && mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      } else if (!unlocked &&
          mounted &&
          revision == _revision &&
          ModalRoute.of(context)?.isCurrent == true) {
        setState(() => _error = '密码不正确');
      }
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = '暂时无法验证，请退格后重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _committing = false;
        });
      }
    }
  }

  ButtonStyle _controlStyle(double size) {
    final colors = Theme.of(context).colorScheme;
    return IconButton.styleFrom(
      fixedSize: Size.square(size),
      iconSize: size * .34,
      padding: EdgeInsets.zero,
      alignment: Alignment.center,
      shape: const CircleBorder(),
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
      disabledBackgroundColor: colors.secondaryContainer,
      disabledForegroundColor: colors.onSecondaryContainer.withValues(
        alpha: .5,
      ),
    );
  }

  Widget _key(int? digit, double size) => SizedBox(
    height: size,
    child: Center(
      child: digit == null
          ? IconButton(
              key: const Key('privacy_pin_delete'),
              tooltip: '删除一位',
              onPressed: _committing || _pin.isEmpty
                  ? null
                  : () => _edit(_pin.substring(0, _pin.length - 1)),
              // Balance the arrow tail so the main symbol is optically centered.
              icon: Transform.translate(
                offset: Offset(-size / 32, 0),
                child: const Icon(Icons.backspace_outlined),
              ),
              style: _controlStyle(size),
            )
          : SizedBox.square(
              dimension: size,
              child: TextButton(
                key: Key('privacy_pin_$digit'),
                onPressed: _committing ? null : () => _digit(digit),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                ),
                child: Text('$digit', style: TextStyle(fontSize: size * .42)),
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_committing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _invalidate();
      },
      child: Scaffold(
        key: const Key('privacy_unlock_screen'),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keypadWidth = (constraints.maxWidth - 48).clamp(0.0, 400.0);
              final keySize = (keypadWidth * .26)
                  .clamp(0.0, constraints.maxHeight * .105)
                  .clamp(48.0, 104.0);
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                    minWidth: constraints.maxWidth,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            appAvatarAsset(widget.settings.value.playfulAvatar),
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Icon(Icons.lock_outline, size: 24),
                        const SizedBox(height: 8),
                        Text(
                          '输入隐私 PIN',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        const Text('解锁后关闭隐私模式', textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        Semantics(
                          label: 'PIN 输入',
                          child: SizedBox(
                            height: 13,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                _pin.length,
                                (_) => Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  width: 13,
                                  height: 13,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _checking ? '正在验证…' : _error ?? '',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _error == null
                                  ? colors.onSurfaceVariant
                                  : colors.error,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.4,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: keypadWidth),
                            child: Column(
                              children: [
                                for (var row = 0; row < 3; row++) ...[
                                  Row(
                                    children: [
                                      for (
                                        var column = 1;
                                        column <= 3;
                                        column++
                                      )
                                        Expanded(
                                          child: _key(
                                            row * 3 + column,
                                            keySize,
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: keySize * .16),
                                ],
                                Row(
                                  children: [
                                    Expanded(child: _key(null, keySize)),
                                    Expanded(child: _key(0, keySize)),
                                    Expanded(
                                      child: Center(
                                        child: IconButton(
                                          key: const Key('privacy_pin_confirm'),
                                          tooltip: '确认解锁',
                                          onPressed:
                                              _checking || _pin.length < 4
                                              ? null
                                              : _check,
                                          icon: Icon(
                                            _checking
                                                ? Icons.hourglass_top
                                                : Icons.check_rounded,
                                          ),
                                          style: _controlStyle(keySize),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _committing ? null : _cancel,
                          style: TextButton.styleFrom(
                            backgroundColor: colors.surfaceContainerHigh,
                            foregroundColor: colors.onSurface,
                            minimumSize: Size(keySize * 1.6, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

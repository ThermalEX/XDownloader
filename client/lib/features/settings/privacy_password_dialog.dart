import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_failure.dart';
import '../../core/security/privacy_password.dart';
import '../../data/repositories/settings_repository.dart';
import 'privacy_unlock_screen.dart';

Future<void> showPrivacyPasswordDialog(
  BuildContext context,
  SettingsRepository settings, {
  bool unlockOnly = false,
}) => unlockOnly
    ? Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => PrivacyUnlockScreen(settings: settings),
        ),
      )
    : showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PasswordDialog(settings: settings),
      );

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.settings});
  final SettingsRepository settings;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _usePassword = true, _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_usePassword) {
      final error =
          PrivacyPasswords.validate(_password.text) ??
          (_password.text != _confirm.text ? '两次输入的密码不一致' : null);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.settings.setPrivacyPassword(
        _usePassword ? _password.text : null,
        currentPassword: _current.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AppFailure ? error.message : '未能保存，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String name, String label, TextEditingController controller) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          key: Key(name),
          controller: controller,
          enabled: !_busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          decoration: InputDecoration(labelText: label, counterText: ''),
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('隐私 PIN'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.settings.value.privacyPasswordHash.isNotEmpty)
            _field('privacy_current_password', '当前 PIN', _current),
          SwitchListTile(
            key: const Key('privacy_use_password'),
            contentPadding: EdgeInsets.zero,
            title: const Text('使用 PIN'),
            value: _usePassword,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _usePassword = value;
                    _error = null;
                  }),
          ),
          if (_usePassword) ...[
            _field('privacy_new_password', '新 PIN（4–6 位数字）', _password),
            _field('privacy_confirm_password', '再次输入新 PIN', _confirm),
            const SizedBox(height: 12),
            const Text('关闭隐私模式时验证。密码仅在本机保存，忘记后无法找回。'),
          ] else
            const Text('关闭隐私模式时不需要密码。'),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
      ],
    ),
  );
}

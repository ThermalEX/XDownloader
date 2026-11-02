import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/request_rotation.dart';
import '../../data/repositories/source_repository.dart';
import 'settings_group.dart';

class RiskProtectionScreen extends StatefulWidget {
  const RiskProtectionScreen({super.key, required this.repository});
  final SourceRepository repository;
  @override
  State<RiskProtectionScreen> createState() => _RiskProtectionState();
}

class _RiskProtectionState extends State<RiskProtectionScreen> {
  bool _saving = false;
  String? _error;
  Future<void> _save(RequestRotation policy) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.setRequestProtection(policy);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is AppFailure ? error.message : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editInterval() async {
    final policy = widget.repository.requestProtection;
    var text = '${policy.interval}';
    final form = GlobalKey<FormState>();
    final interval = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('轮换间隔'),
        scrollable: true,
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: text,
            onChanged: (value) => text = value,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: policy.mode == RotationMode.minutes
                  ? '间隔（分钟）'
                  : '间隔（解析次数）',
            ),
            validator: (value) {
              final number = int.tryParse(value ?? '');
              return number == null || number < 1 || number > policy.maximum
                  ? '请输入 1–${policy.maximum} 的整数'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, int.parse(text));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (mounted && interval != null) {
      await _save(RequestRotation(policy.mode, interval));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('风控保护')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.repository,
        builder: (context, _) {
          final policy = widget.repository.requestProtection;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsPanel(
                title: '请求配置轮换',
                child: RadioGroup<RotationMode>(
                  groupValue: policy.mode,
                  onChanged: (mode) {
                    if (mode != null && mode != policy.mode && !_saving) {
                      _save(
                        RequestRotation(
                          mode,
                          mode == RotationMode.count ? 10 : 15,
                        ),
                      );
                    }
                  },
                  child: Column(
                    children: [
                      for (final row in [
                        (RotationMode.off, '关闭'),
                        (RotationMode.minutes, '按时间'),
                        (RotationMode.count, '按解析次数'),
                      ])
                        RadioListTile<RotationMode>(
                          value: row.$1,
                          title: Text(row.$2),
                          enabled: !_saving,
                        ),
                    ],
                  ),
                ),
              ),
              if (policy.mode != RotationMode.off)
                SettingsPanel(
                  child: ListTile(
                    leading: const SettingsIcon(Icons.timer_outlined),
                    title: const Text('轮换间隔'),
                    subtitle: Text(policy.description),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _saving ? null : _editInterval,
                  ),
                ),
              const SettingsPanel(
                title: '限流处理',
                child: ListTile(
                  leading: SettingsIcon(Icons.shield_outlined),
                  title: Text('限流后自动冷却'),
                  subtitle: Text('遵守网站的等待时间；开启自动换源时尝试其他源。关闭请求轮换也会保留限流冷却。'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '所有下载源共用此设置，各源独立计时、计数，同一次解析保持一致。成功或失败均计次，取消不计，重启后重新计数。VxTwitter 保留专用标识。',
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('仅调整请求标识和语言，不改变网络 IP，也不能保证解除网站限制。'),
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

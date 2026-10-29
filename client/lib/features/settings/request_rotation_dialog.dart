import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/request_rotation.dart';
import '../../core/models/source.dart';
import '../../data/repositories/source_repository.dart';

class RequestRotationDialog extends StatefulWidget {
  const RequestRotationDialog({
    super.key,
    required this.source,
    required this.repository,
  });
  final ParseSource source;
  final SourceRepository repository;
  @override
  State<RequestRotationDialog> createState() => _RequestRotationDialogState();
}

class _RequestRotationDialogState extends State<RequestRotationDialog> {
  final _form = GlobalKey<FormState>();
  late RotationMode _mode = widget.repository
      .rotationFor(widget.source.id)
      .mode;
  late final _interval = TextEditingController(
    text: '${widget.repository.rotationFor(widget.source.id).interval}',
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.setRotation(
        widget.source.id,
        RequestRotation(
          _mode,
          _mode == RotationMode.off ? 15 : int.parse(_interval.text),
        ),
      );
      if (mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('请求配置轮换'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.source.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<RotationMode>(
              initialValue: _mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '轮换方式'),
              items: const [
                DropdownMenuItem(value: RotationMode.off, child: Text('关闭')),
                DropdownMenuItem(
                  value: RotationMode.minutes,
                  child: Text('按时间'),
                ),
                DropdownMenuItem(
                  value: RotationMode.count,
                  child: Text('按解析次数'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (mode) => setState(() {
                      _mode = mode!;
                      _interval.text = mode == RotationMode.count ? '10' : '15';
                    }),
            ),
            if (_mode != RotationMode.off) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _interval,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: _mode == RotationMode.minutes
                      ? '间隔（分钟）'
                      : '间隔（解析次数）',
                ),
                validator: (text) {
                  final number = int.tryParse(text ?? '');
                  final maximum = _mode == RotationMode.minutes ? 1440 : 1000;
                  return number == null || number < 1 || number > maximum
                      ? '请输入 1–$maximum 的整数'
                      : null;
                },
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '仅轮换浏览器标识和语言请求头，不改变 IP 或 TLS 指纹，也不能保证解除网站限制。同一次解析保持一致，达到频率后在下次解析开始时更换。',
            ),
            const SizedBox(height: 12),
            const Text(
              '次数按此源已结束的解析计算，成功或失败均计入，取消不计。重启后重新计数。遇到限流先冷却，开启自动换源时尝试其他源。',
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
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存…' : '保存'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/naming/file_naming.dart';
import '../../data/repositories/settings_repository.dart';

import 'settings_group.dart';

class NamingSettingsScreen extends StatefulWidget {
  const NamingSettingsScreen({super.key, required this.repository});
  final SettingsRepository repository;
  @override
  State<NamingSettingsScreen> createState() => _NamingState();
}

class _NamingState extends State<NamingSettingsScreen> {
  late final _text = TextEditingController(
    text: widget.repository.value.fileNameTemplate,
  );
  bool _saving = false;
  late bool _original = widget.repository.value.useOriginalFileName;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _original ? null : FileNaming.validateTemplate(_text.text);
    return Scaffold(
      appBar: AppBar(title: const Text('重命名规则')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('只影响之后下载的文件，已保存的文件保持原名。系统会自动清理文件名中的非法字符。'),
            const SizedBox(height: 20),
            SettingsPanel(
              title: '命名方式',
              child: RadioGroup<bool>(
                groupValue: _original,
                onChanged: (value) {
                  if (!_saving && value != null) {
                    setState(() => _original = value);
                  }
                },
                child: const Column(
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      title: Text('原始标题'),
                      subtitle: Text('使用解析到的视频标题'),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      title: Text('自定义规则'),
                      subtitle: Text('组合标题、作者、日期等信息'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SettingsPanel(
              title: '自定义模板',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  key: const Key('filename_template'),
                  controller: _text,
                  enabled: !_original && !_saving,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '文件名模板',
                    errorText: error,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SettingsPanel(
              title: '预览与变量',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '文件名预览',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      error == null
                          ? FileNaming.preview(
                              _original ? '{title}' : _text.text,
                            )
                          : '输入有效模板后显示预览',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '{title} 标题\n{author} 作者\n{postId} 帖子编号\n{index} 视频序号\n{width} 宽度 · {height} 高度\n{resolution} 分辨率\n{date} 日期，如 2026-10-21\n{time} 时间，如 02-05-09\n{datetime} 日期与时间，如 2026-10-21_02-05-09\n\n日期和时间取开始下载时的设备当地时间。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _original = false;
                          _text.text = FileNaming.defaultTemplate;
                        }),
                  child: const Text('恢复默认'),
                ),
                FilledButton(
                  onPressed: _saving || error != null
                      ? null
                      : () => runAction(context, () async {
                          setState(() => _saving = true);
                          try {
                            final template = _text.text.trim();
                            final valid =
                                FileNaming.validateTemplate(template) == null;
                            await widget.repository.edit(
                              (s) => s.copyWith(
                                useOriginalFileName: _original,
                                fileNameTemplate: valid
                                    ? template
                                    : s.fileNameTemplate,
                              ),
                            );
                            if (context.mounted) Navigator.pop(context);
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        }),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

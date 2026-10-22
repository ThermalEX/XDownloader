import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../app/app_shell.dart';
import '../../core/naming/file_naming.dart';
import '../../core/naming/naming_draft.dart';
import '../../data/repositories/settings_repository.dart';
import 'settings_group.dart';

class NamingSettingsScreen extends StatefulWidget {
  const NamingSettingsScreen({super.key, required this.repository});
  final SettingsRepository repository;
  @override
  State<NamingSettingsScreen> createState() => _NamingState();
}

class _NamingState extends State<NamingSettingsScreen> {
  late NamingDraft _draft = NamingDraft(
    widget.repository.value.fileNameTemplate,
  );
  late final _separator = TextEditingController(text: _draft.separator);
  late bool _original = widget.repository.value.useOriginalFileName;
  bool _saving = false;
  String? _separatorError;
  static const _labels = {
    'title': '标题',
    'author': '作者',
    'postId': '帖子编号',
    'index': '视频序号',
    'resolution': '分辨率',
    'width': '宽度',
    'height': '高度',
    'date': '日期',
    'time': '时间',
    'datetime': '日期时间',
  };
  @override
  void dispose() {
    _separator.dispose();
    super.dispose();
  }

  void _move(int from, int to) {
    if (!_original && !_saving) setState(() => _draft.move(from, to));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_original && !_saving;
    final error = _original
        ? null
        : _separatorError ?? FileNaming.validateTemplate(_draft.template);
    final validDraft = FileNaming.validateTemplate(_draft.template) == null;
    return Scaffold(
      appBar: AppBar(title: const Text('重命名规则')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SettingsPanel(
              title: '命名方式',
              child: RadioGroup<bool>(
                groupValue: _original,
                onChanged: (value) {
                  if (!_saving && value != null) {
                    setState(() => _original = value);
                  }
                },
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      value: true,
                      title: const Text('原始标题'),
                      subtitle: Text(FileNaming.preview('{title}')),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      title: const Text('自定义规则'),
                      subtitle: Text(
                        validDraft
                            ? FileNaming.preview(_draft.template)
                            : '请选择命名标签',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SettingsPanel(
              title: '标签顺序',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('点击下方标签添加，长按左右拖动排序'),
                    const SizedBox(height: 8),
                    if (_draft.fields.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('还没有命名标签'),
                      ),
                    SizedBox(
                      height:
                          56 *
                              (MediaQuery.textScalerOf(context).scale(14) /
                                  14) +
                          24,
                      child: ReorderableListView.builder(
                        key: const Key('naming_order'),
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemCount: _draft.fields.length,
                        onReorderItem: _move,
                        itemBuilder: (context, index) {
                          final field = _draft.fields[index];
                          return Padding(
                            key: ValueKey(field.id),
                            padding: const EdgeInsets.only(right: 8),
                            child: Semantics(
                              customSemanticsActions: {
                                if (enabled && index > 0)
                                  CustomSemanticsAction(label: '向左移动'): () =>
                                      _move(index, index - 1),
                                if (enabled && index + 1 < _draft.fields.length)
                                  CustomSemanticsAction(label: '向右移动'): () =>
                                      _move(index, index + 1),
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ReorderableDelayedDragStartListener(
                                    index: index,
                                    enabled: enabled,
                                    child: InputChip(
                                      key: Key('naming_field_${field.id}'),
                                      avatar: const Icon(
                                        Icons.drag_indicator,
                                        size: 18,
                                      ),
                                      label: Text(_labels[field.name]!),
                                      isEnabled: enabled,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.padded,
                                      onDeleted: enabled
                                          ? () => setState(
                                              () => _draft.remove(index),
                                            )
                                          : null,
                                      deleteButtonTooltipMessage:
                                          '移除${_labels[field.name]}',
                                    ),
                                  ),
                                  if (index < _draft.separators.length)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(_draft.separators[index]),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (error != null)
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SettingsPanel(
              title: '添加标签',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in _labels.entries)
                      ActionChip(
                        key: Key('naming_add_${entry.key}'),
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(entry.value),
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onPressed: enabled
                            ? () => setState(() => _draft.add(entry.key))
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            SettingsPanel(
              title: '分隔符',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  key: const Key('naming_separator'),
                  controller: _separator,
                  enabled: enabled,
                  maxLength: 16,
                  decoration: InputDecoration(
                    labelText: '分隔符（修改后统一应用）',
                    hintText: '例如 _ 或 -，留空则直接连接',
                    errorText: _separatorError,
                  ),
                  onChanged: (value) => setState(() {
                    try {
                      _draft.setSeparator(value);
                      _separatorError = null;
                    } on FormatException catch (error) {
                      _separatorError = error.message;
                    }
                  }),
                ),
              ),
            ),
            SettingsPanel(
              title: '文件名预览',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      _original
                          ? FileNaming.preview('{title}')
                          : validDraft
                          ? FileNaming.preview(_draft.template)
                          : '请选择命名标签',
                    ),
                    const SizedBox(height: 12),
                    const Text('日期和时间取开始下载时的设备当地时间。规则只影响之后的下载。'),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _original = false;
                          _draft = NamingDraft(FileNaming.defaultTemplate);
                          _separator.text = _draft.separator;
                          _separatorError = null;
                        }),
                  child: const Text('恢复默认'),
                ),
                FilledButton(
                  onPressed: _saving || error != null
                      ? null
                      : () => runAction(context, () async {
                          FocusScope.of(context).unfocus();
                          setState(() => _saving = true);
                          try {
                            final template = _draft.template.trim();
                            await widget.repository.edit(
                              (s) => s.copyWith(
                                useOriginalFileName: _original,
                                fileNameTemplate:
                                    FileNaming.validateTemplate(template) ==
                                        null
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

import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/models/source.dart';
import '../../data/repositories/source_repository.dart';

import 'settings_group.dart';

class SourceEditorScreen extends StatefulWidget {
  const SourceEditorScreen({super.key, required this.repository, this.source});
  final SourceRepository repository;
  final ParseSource? source;
  @override
  State<SourceEditorScreen> createState() => _EditorState();
}

class _EditorState extends State<SourceEditorScreen> {
  late final TextEditingController name, endpoint, body;
  late SourceKind kind;
  late String method;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.source?.name);
    endpoint = TextEditingController(text: widget.source?.endpoint);
    body = TextEditingController(text: widget.source?.body);
    kind = widget.source?.kind ?? SourceKind.scrape;
    method = widget.source?.method ?? 'GET';
  }

  @override
  void dispose() {
    name.dispose();
    endpoint.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
    });
    try {
      await widget.repository.addCustom(
        ParseSource(
          widget.source?.id ?? '',
          name.text,
          endpoint.text,
          kind,
          method,
          body.text,
          false,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.source == null ? '添加解析源' : '编辑解析源')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SettingsPanel(
            title: '解析源配置',
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('source_name'),
                    controller: name,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('source_endpoint'),
                    controller: endpoint,
                    keyboardType: TextInputType.url,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: '接口地址',
                      helperText: '支持 {url}、{urlenc}、{id}、{user}',
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SourceKind>(
                    borderRadius: BorderRadius.circular(20),
                    initialValue: kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '响应格式'),
                    items: [
                      for (final k in SourceKind.values)
                        DropdownMenuItem(value: k, child: Text(k.name)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          kind = v;
                        });
                      }
                    },
                  ),
                  if (kind == SourceKind.scrape) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      borderRadius: BorderRadius.circular(20),
                      initialValue: method,
                      decoration: const InputDecoration(labelText: '请求方法'),
                      items: const [
                        DropdownMenuItem(value: 'GET', child: Text('GET')),
                        DropdownMenuItem(value: 'POST', child: Text('POST')),
                      ],
                      onChanged: (v) => setState(() {
                        method = v!;
                      }),
                    ),
                    if (method == 'POST')
                      TextField(
                        controller: body,
                        decoration: const InputDecoration(
                          labelText: '表单正文（可选）',
                        ),
                        maxLines: 3,
                      ),
                  ],
                  if (kind == SourceKind.xdl)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('XDL 格式使用固定的 JSON POST 请求。'),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: const Text('保存'),
                  ),
                  if (widget.source != null)
                    TextButton(
                      onPressed: () async {
                        await runAction(
                          context,
                          () => widget.repository.remove(widget.source!.id),
                        );
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('删除解析源'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

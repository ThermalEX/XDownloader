import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_failure.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/source_repository.dart';
import '../../core/parsing/parse_client.dart';
import 'source_editor_screen.dart';
import 'source_health_controller.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({
    super.key,
    required this.repository,
    this.parser,
    this.readClipboard,
  });
  final SourceRepository repository;
  final ParseClient? parser;
  final Future<String?> Function()? readClipboard;
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late final _health = SourceHealthController(widget.parser ?? ParseClient());
  SourceRepository get repository => widget.repository;
  bool _exchanging = false;
  Future<void> _exchange(bool importing) => runAction(context, () async {
    if (_exchanging) return;
    setState(() => _exchanging = true);
    try {
      String message;
      if (importing) {
        final text =
            await (widget.readClipboard?.call() ??
                Clipboard.getData(Clipboard.kTextPlain)
                    .then((data) => data?.text));
        if (!mounted) return;
        if (text == null || text.trim().isEmpty) {
          throw const AppFailure(FailureKind.malformed, '剪贴板中没有源配置');
        }
        final added = await repository.importSources(text);
        message = added == 0 ? '没有新增解析源，已有配置保持不变' : '已导入 $added 个解析源';
      } else {
        await Clipboard.setData(
          ClipboardData(text: repository.exportSources()),
        );
        message = '已将解析源配置复制到剪贴板';
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _exchanging = false);
    }
  });
  @override
  void dispose() {
    _health.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('下载源'),
      actions: [
        PopupMenuButton<bool>(
          tooltip: '源导入与导出',
          enabled: !_exchanging,
          icon: const Icon(Icons.import_export),
          onSelected: _exchange,
          itemBuilder: (_) => const [
            PopupMenuItem(value: true, child: Text('从剪贴板导入')),
            PopupMenuItem(value: false, child: Text('导出到剪贴板')),
          ],
        ),
        IconButton(
          tooltip: '添加解析源',
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SourceEditorScreen(repository: repository),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([repository, _health]),
        builder: (context, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('失败后自动换源'),
              value: repository.autoFallback,
              onChanged: (value) =>
                  runAction(context, () => repository.setFallback(value)),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('先尝试选中的源；开启自动换源后，失败时尝试其他源。'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _health.checkingAll
                        ? null
                        : () => _health.checkAll(repository.list.toList()),
                    icon: const Icon(Icons.network_check),
                    label: Text(_health.checkingAll ? '正在检测全部…' : '检测全部'),
                  ),
                  const SizedBox(height: 8),
                  const Text('用示例视频检测解析能力；结果仅供参考，不会切换当前源。'),
                ],
              ),
            ),
            for (final source in repository.list)
              ListTile(
                title: Text(source.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.builtin ? '内置解析源' : source.endpoint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_health.checking(source.id))
                      const Text('正在检测…')
                    else if (_health.result(source.id) case final result?)
                      Text(result),
                  ],
                ),
                leading: Icon(
                  repository.currentId == source.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () =>
                    runAction(context, () => repository.select(source.id)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '检测 ${source.name}',
                      onPressed: _health.checking(source.id)
                          ? null
                          : () => _health.check(source),
                      icon: _health.checking(source.id)
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check),
                    ),
                    if (!source.builtin)
                      IconButton(
                        tooltip: '编辑解析源',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => SourceEditorScreen(
                              repository: repository,
                              source: source,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

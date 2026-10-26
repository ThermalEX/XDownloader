import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/app_failure.dart';
import '../../core/models/source.dart';
import '../../core/parsing/source_exchange.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/source_repository.dart';
import '../../core/parsing/parse_client.dart';
import 'source_editor_screen.dart';
import 'source_health_controller.dart';

import 'settings_group.dart';

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
  late final _health = SourceHealthController(
    widget.parser ?? ParseClient(),
    repository: repository,
  );
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
        final imported = SourceExchange.decode(text);
        final selection = await showDialog<Set<int>>(
          context: context,
          builder: (_) =>
              _SourceSelectionDialog(sources: imported, importing: true),
        );
        if (selection == null || !mounted) return;
        final added = await repository.importSources(
          text,
          selectedIndices: selection,
        );
        message = added == 0 ? '没有新增解析源，已有配置保持不变' : '已导入 $added 个解析源';
      } else {
        final sources = repository.list;
        final selection = await showDialog<Set<int>>(
          context: context,
          builder: (_) =>
              _SourceSelectionDialog(sources: sources, importing: false),
        );
        if (selection == null || !mounted) return;
        await Clipboard.setData(
          ClipboardData(
            text: repository.exportSources(
              ids: selection.map((i) => sources[i].id).toSet(),
            ),
          ),
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
          padding: const EdgeInsets.all(16),
          children: [
            SettingsPanel(
              title: '解析行为',
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('失败后自动换源'),
                    subtitle: const Text(
                      '手选源优先，备用源按列表顺序尝试；菜单可调整顺序，近期失败的备用源暂时跳过',
                    ),
                    value: repository.autoFallback,
                    onChanged: (value) =>
                        runAction(context, () => repository.setFallback(value)),
                  ),
                ],
              ),
            ),
            SettingsPanel(
              title: '源检测',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _health.checkingAll
                            ? null
                            : () => _health.checkAll(repository.list.toList()),
                        icon: const Icon(Icons.network_check),
                        label: Text(_health.checkingAll ? '正在检测全部…' : '检测全部'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final source in repository.list)
              SettingsPanel(
                child: ListTile(
                  title: Text(source.name),
                  subtitle:
                      source.builtin &&
                          !_health.checking(source.id) &&
                          _health.result(source.id) == null
                      ? null
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!source.builtin)
                              Text(
                                source.endpoint,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (_health.checking(source.id))
                              const Text('正在检测…')
                            else if (_health.result(source.id)
                                case final result?)
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.network_check),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '${source.name} 操作',
                        onSelected: (action) => runAction(context, () async {
                          if (action == 'export') {
                            await Clipboard.setData(
                              ClipboardData(
                                text: repository.exportSources(
                                  ids: {source.id},
                                ),
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制此源配置')),
                              );
                            }
                          } else if (action == 'up' || action == 'down') {
                            await repository.movePriority(
                              source.id,
                              action == 'up' ? -1 : 1,
                            );
                          } else {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => SourceEditorScreen(
                                  repository: repository,
                                  source: source,
                                ),
                              ),
                            );
                          }
                        }),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'up',
                            enabled: repository.list.first.id != source.id,
                            child: const Text('提高优先级'),
                          ),
                          PopupMenuItem(
                            value: 'down',
                            enabled: repository.list.last.id != source.id,
                            child: const Text('降低优先级'),
                          ),
                          const PopupMenuItem(
                            value: 'export',
                            child: Text('导出此源'),
                          ),
                          if (!source.builtin)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑解析源'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SourceSelectionDialog extends StatefulWidget {
  const _SourceSelectionDialog({
    required this.sources,
    required this.importing,
  });
  final List<ParseSource> sources;
  final bool importing;
  @override
  State<_SourceSelectionDialog> createState() => _SourceSelectionState();
}

class _SourceSelectionState extends State<_SourceSelectionDialog> {
  final _selected = <int>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.importing ? '选择要导入的源' : '选择要导出的源'),
    content: SizedBox(
      width: 420,
      height: MediaQuery.sizeOf(context).height * .45,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '已选择 ${_selected.length} / ${widget.sources.length}',
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (_selected.length == widget.sources.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(
                      List.generate(widget.sources.length, (i) => i),
                    );
                  }
                }),
                child: Text(
                  _selected.length == widget.sources.length ? '取消全选' : '全选',
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.sources.length,
              itemBuilder: (context, index) {
                final source = widget.sources[index];
                return CheckboxListTile(
                  key: Key('source_pick_$index'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(source.name),
                  subtitle: Text(
                    source.endpoint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  value: _selected.contains(index),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      _selected.add(index);
                    } else {
                      _selected.remove(index);
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, Set<int>.of(_selected)),
        child: Text(
          '${widget.importing ? '导入所选' : '复制所选'} (${_selected.length})',
        ),
      ),
    ],
  );
}

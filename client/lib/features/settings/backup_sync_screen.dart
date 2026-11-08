import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/backup/backup_archive.dart';
import '../../data/backup/webdav_client.dart';
import '../../data/repositories/backup_repository.dart';
import 'settings_group.dart';

/// Opens the same privacy-guarded cloud history used by the settings page.
Widget cloudBackupArchives(BackupRepository repository) =>
    _ArchiveListScreen(repository: repository, remote: true);

const _sectionNames = {
  'favorites': '收藏',
  'settings': '应用设置',
  'sources': '下载源',
  'updates': '更新偏好',
};
const _privateMessage = '隐私模式下不可查看或备份';

/// Every route and modal builds its sensitive content behind the same live
/// repository guard. Captured archives never bypass a later privacy change.
class _Guard extends StatelessWidget {
  const _Guard({
    required this.repository,
    required this.builder,
    this.dialog = false,
  });
  final BackupRepository repository;
  final WidgetBuilder builder;
  final bool dialog;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (context, _) {
      if (!repository.isPrivate) return builder(context);
      if (dialog) {
        return AlertDialog(
          title: const Text('备份与同步'),
          content: const Text(_privateMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('备份与同步')),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(_privateMessage),
            ),
          ),
        ),
      );
    },
  );
}

Future<T?> _act<T>(
  BuildContext context,
  BackupRepository repository,
  Future<T> Function() action,
) async {
  if (repository.isPrivate || repository.busy) return null;
  try {
    final result = await action();
    return repository.isPrivate ? null : result;
  } catch (error) {
    if (context.mounted && !repository.isPrivate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            repository.error ??
                (error is FormatException ? error.message : '操作失败，请重试'),
          ),
        ),
      );
    }
    return null;
  }
}

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => page));

Widget _page(
  BuildContext context,
  String title,
  List<Widget> children, {
  List<Widget>? actions,
}) => Scaffold(
  appBar: AppBar(title: Text(title), actions: actions),
  body: SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: children,
    ),
  ),
);

Widget _status(BackupRepository repository) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (repository.recentBackupAt case final time?)
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('最近成功备份：${_time(time)}'),
      ),
    if (repository.recentCheckAt case final time?)
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('最近云端检测：${_time(time)}'),
      ),
    if (repository.busy)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      ),
    if (repository.status case final text?)
      Padding(padding: const EdgeInsets.all(12), child: Text(text)),
    if (repository.error case final text?)
      Padding(padding: const EdgeInsets.all(12), child: Text(text)),
  ],
);

String _time(DateTime? time) {
  if (time == null) return '未知';
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _size(int? bytes) => bytes == null
    ? '大小未知'
    : bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB'
    : bytes >= 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
    : '$bytes B';

class BackupSyncScreen extends StatefulWidget {
  const BackupSyncScreen({super.key, required this.repository});
  final BackupRepository repository;
  @override
  State<BackupSyncScreen> createState() => _BackupSyncScreenState();
}

class _BackupSyncScreenState extends State<BackupSyncScreen> {
  final _sections = {...BackupArchive.sections};
  BackupLocation? _location;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return _Guard(
      repository: repository,
      builder: (context) {
        final configured = repository.config != null;
        final location = configured
            ? _location ?? BackupLocation.both
            : BackupLocation.local;
        return _page(context, '备份与同步', [
          _status(repository),
          SettingsGroup(
            title: '云端配置',
            grouped: true,
            children: [
              ListTile(
                key: const Key('backup_config'),
                leading: const SettingsIcon(Icons.cloud_outlined),
                title: const Text('WebDAV 配置'),
                subtitle: Text(
                  repository.config?.endpoint.host ?? '未配置，仍可使用本地备份',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: repository.busy
                    ? null
                    : () =>
                          _push(context, _ConfigScreen(repository: repository)),
              ),
              SwitchListTile(
                title: const Text('启动时检查云端存档'),
                subtitle: const Text('仅检测并提示，由你选择下载和恢复'),
                value: repository.autoCheck,
                onChanged: !configured || repository.busy
                    ? null
                    : (value) => _act(
                        context,
                        repository,
                        () => repository.setAutoCheck(value),
                      ),
              ),
            ],
          ),
          SettingsGroup(
            title: '备份内容',
            grouped: true,
            children: [
              for (final section in _sectionNames.entries)
                CheckboxListTile(
                  title: Text(section.value),
                  value: _sections.contains(section.key),
                  onChanged: repository.busy
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _sections.add(section.key);
                          } else {
                            _sections.remove(section.key);
                          }
                        }),
                ),
            ],
          ),
          SettingsGroup(
            title: '保存位置',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<BackupLocation>(
                  key: ValueKey('backup_location_$location'),
                  initialValue: location,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '保存到',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: BackupLocation.local,
                      child: Text('仅本地'),
                    ),
                    if (configured) ...[
                      const DropdownMenuItem(
                        value: BackupLocation.cloud,
                        child: Text('仅云端'),
                      ),
                      const DropdownMenuItem(
                        value: BackupLocation.both,
                        child: Text('本地和云端'),
                      ),
                    ],
                  ],
                  onChanged: repository.busy
                      ? null
                      : (value) => setState(() => _location = value),
                ),
              ),
            ],
          ),
          FilledButton.icon(
            key: const Key('backup_create'),
            onPressed: repository.busy || _sections.isEmpty
                ? null
                : () => _act(
                    context,
                    repository,
                    () => repository.create(
                      sections: {..._sections},
                      location: location,
                    ),
                  ),
            icon: const Icon(Icons.backup_outlined),
            label: const Text('立即备份'),
          ),
          SettingsGroup(
            title: '存档',
            grouped: true,
            children: [
              ListTile(
                key: const Key('backup_local'),
                leading: const SettingsIcon(Icons.folder_outlined),
                title: const Text('本地存档'),
                subtitle: const Text('选择时间点、导出或恢复'),
                trailing: const Icon(Icons.chevron_right),
                onTap: repository.busy
                    ? null
                    : () => _push(
                        context,
                        _ArchiveListScreen(
                          repository: repository,
                          remote: false,
                        ),
                      ),
              ),
              ListTile(
                key: const Key('backup_cloud'),
                leading: const SettingsIcon(Icons.cloud_download_outlined),
                title: const Text('云端存档'),
                subtitle: const Text('浏览历史存档，选择一份下载到本地'),
                trailing: const Icon(Icons.chevron_right),
                onTap: !configured || repository.busy
                    ? null
                    : () => _push(
                        context,
                        _ArchiveListScreen(
                          repository: repository,
                          remote: true,
                        ),
                      ),
              ),
              ListTile(
                leading: const SettingsIcon(Icons.file_open_outlined),
                title: const Text('导入存档文件'),
                subtitle: const Text('先保存到本地，不会自动恢复'),
                onTap: repository.busy
                    ? null
                    : () async {
                        final archive = await _act(
                          context,
                          repository,
                          repository.importFile,
                        );
                        if (archive != null &&
                            context.mounted &&
                            !repository.isPrivate) {
                          await _push(
                            context,
                            _LocalDetailScreen(
                              repository: repository,
                              archive: archive,
                            ),
                          );
                        }
                      },
              ),
            ],
          ),
        ]);
      },
    );
  }
}

class _ConfigScreen extends StatefulWidget {
  const _ConfigScreen({required this.repository});
  final BackupRepository repository;
  @override
  State<_ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<_ConfigScreen> {
  late final TextEditingController _endpoint,
      _username,
      _password,
      _folder,
      _device;
  late bool _allowHttp, _autoCheck;
  String? _error;
  @override
  void initState() {
    super.initState();
    final config = widget.repository.config;
    _endpoint = TextEditingController(text: config?.endpoint.toString() ?? '');
    _username = TextEditingController(text: config?.username ?? '');
    _password = TextEditingController();
    _folder = TextEditingController(text: config?.folder ?? 'XDownloader');
    _device = TextEditingController(text: widget.repository.deviceName);
    _allowHttp = config?.allowHttp ?? false;
    _autoCheck = widget.repository.autoCheck;
  }

  @override
  void dispose() {
    for (final controller in [
      _endpoint,
      _username,
      _password,
      _folder,
      _device,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool test = false}) async {
    final repository = widget.repository;
    if (repository.isPrivate || repository.busy) return;
    WebDavConfig config;
    try {
      config = WebDavConfig(
        endpoint: Uri.parse(_endpoint.text.trim()),
        username: _username.text,
        folder: _folder.text.trim(),
        allowHttp: _allowHttp,
      );
      if (_device.text.trim().isEmpty) throw const FormatException('请填写设备名称');
    } catch (_) {
      setState(() => _error = '请检查服务器地址、文件夹和设备名称；HTTP 需先确认传输风险');
      return;
    }
    setState(() => _error = null);
    final saved = await _act(context, repository, () async {
      await repository.configure(
        config: config,
        password: _password.text,
        deviceName: _device.text.trim(),
        autoCheck: _autoCheck,
      );
      return true;
    });
    if (saved != true || !mounted || repository.isPrivate) return;
    _password.clear();
    if (test) {
      await _act(context, repository, repository.testConnection);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('WebDAV 配置已保存')));
    }
  }

  Widget _field(
    String name,
    TextEditingController controller, {
    Key? key,
    bool secret = false,
    String? helper,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: key,
      controller: controller,
      obscureText: secret,
      autocorrect: !secret,
      enableSuggestions: !secret,
      decoration: InputDecoration(
        labelText: name,
        hintText: hint,
        floatingLabelBehavior: hint == null
            ? FloatingLabelBehavior.auto
            : FloatingLabelBehavior.always,
        hintStyle: TextStyle(color: Theme.of(context).hintColor),
        helperText: helper,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => _Guard(
    repository: widget.repository,
    builder: (context) => _page(context, 'WebDAV 配置', [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '存档是未加密的 ZIP 数据包，可能含私人收藏链接和自定义源令牌，将保存在你自己的 WebDAV 目录。SHA-256 只校验完整性。',
        ),
      ),
      _field(
        '服务器地址',
        _endpoint,
        key: const Key('webdav_endpoint'),
        hint: 'https://dav.example.com/dav/',
        helper: '推荐 HTTPS；地址不能包含用户名、密码或查询参数',
      ),
      _field('用户名', _username),
      _field(
        '密码或应用专用密码',
        _password,
        secret: true,
        helper: '留空保留同一服务器、账号的已有密码；更换服务器或账号需重新填写。密码不会写入存档',
      ),
      _field(
        '文件夹',
        _folder,
        helper: '相对于服务器地址，例如 XDownloader 或 backup/XDownloader',
      ),
      _field('设备名称', _device),
      CheckboxListTile(
        key: const Key('webdav_allow_http'),
        contentPadding: EdgeInsets.zero,
        title: const Text('允许 HTTP 明文传输'),
        subtitle: const Text('HTTP 会明文传输账户凭据与存档；仅在明确接受该风险时开启'),
        value: _allowHttp,
        onChanged: widget.repository.busy
            ? null
            : (value) => setState(() => _allowHttp = value == true),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('启动时检查云端存档'),
        value: _autoCheck,
        onChanged: widget.repository.busy
            ? null
            : (value) => setState(() => _autoCheck = value),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      _status(widget.repository),
      FilledButton(
        key: const Key('webdav_save'),
        onPressed: widget.repository.busy ? null : _save,
        child: const Text('保存配置'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: widget.repository.busy ? null : () => _save(test: true),
        child: const Text('保存并测试连接'),
      ),
    ]),
  );
}

class _ArchiveListScreen extends StatefulWidget {
  const _ArchiveListScreen({required this.repository, required this.remote});
  final BackupRepository repository;
  final bool remote;
  @override
  State<_ArchiveListScreen> createState() => _ArchiveListScreenState();
}

class _ArchiveListScreenState extends State<_ArchiveListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.repository.isPrivate) _refresh();
    });
  }

  Future<void> _refresh() async {
    await _act(
      context,
      widget.repository,
      widget.remote
          ? widget.repository.refreshRemote
          : widget.repository.refreshLocal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return _Guard(
      repository: repository,
      builder: (context) {
        final local = [...repository.localArchives]
          ..sort((a, b) {
            final time = b.archive.createdAt.compareTo(a.archive.createdAt);
            return time != 0 ? time : a.archive.id.compareTo(b.archive.id);
          });
        final remote = [...repository.remoteEntries]
          ..sort((a, b) {
            final time =
                (b.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      a.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    );
            return time != 0 ? time : a.name.compareTo(b.name);
          });
        final count = widget.remote ? remote.length : local.length;
        return _page(
          context,
          widget.remote ? '云端存档' : '本地存档',
          [
            _status(repository),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                widget.remote
                    ? '$count 份云端存档；下载不会修改当前数据'
                    : '$count 份本地存档 · ${_size(local.fold<int>(0, (sum, item) => sum + item.bytes))}',
              ),
            ),
            if (repository.error != null)
              OutlinedButton(
                onPressed: repository.busy ? null : _refresh,
                child: const Text('重试'),
              ),
            if (count == 0 && !repository.busy)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(widget.remote ? '暂无云端存档' : '暂无本地存档'),
              ),
            if (widget.remote)
              for (final entry in remote)
                SettingsPanel(
                  child: ListTile(
                    key: Key('remote_${entry.fingerprint}'),
                    title: Text(
                      entry.name.replaceFirst(RegExp(r'\.zip$'), ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '云端修改时间：${_time(entry.modifiedAt)}\n${_size(entry.bytes)}\n内容：下载校验后查看',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: repository.busy
                        ? null
                        : () => _push(
                            context,
                            _RemoteDetailScreen(
                              repository: repository,
                              entry: entry,
                            ),
                          ),
                  ),
                ),
            if (!widget.remote)
              for (final item in local)
                SettingsPanel(
                  child: ListTile(
                    key: Key('local_${item.archive.id}'),
                    title: Text(_time(item.archive.createdAt)),
                    subtitle: Text(
                      '${item.archive.deviceName} · ${_size(item.bytes)}\n${_contents(item.archive)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: repository.busy
                        ? null
                        : () => _push(
                            context,
                            _LocalDetailScreen(
                              repository: repository,
                              archive: item.archive,
                            ),
                          ),
                  ),
                ),
          ],
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: repository.busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        );
      },
    );
  }
}

int? _localBytes(BackupRepository repository, BackupArchive archive) {
  for (final local in repository.localArchives) {
    if (local.archive.id == archive.id &&
        local.archive.digest == archive.digest) {
      return local.bytes;
    }
  }
  return null;
}

String _contents(BackupArchive archive) => archive.data.entries
    .map((entry) {
      if (entry.key == 'favorites') {
        return '收藏 ${(entry.value['items'] as List).length} 条';
      }
      if (entry.key == 'sources') {
        return '自定义源 ${(entry.value['custom'] as List).length} 个';
      }
      return _sectionNames[entry.key]!;
    })
    .join(' · ');

Future<bool> _confirm(
  BuildContext context,
  BackupRepository repository,
  String title,
  String message,
) async =>
    await showDialog<bool>(
          context: context,
          builder: (_) => _Guard(
            repository: repository,
            dialog: true,
            builder: (context) => AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          ),
        ) ==
        true &&
    !repository.isPrivate;

Future<void> _restore(
  BuildContext context,
  BackupRepository repository,
  BackupArchive archive,
) => _push(context, _RestoreScreen(repository: repository, archive: archive));

class _LocalDetailScreen extends StatelessWidget {
  const _LocalDetailScreen({required this.repository, required this.archive});
  final BackupRepository repository;
  final BackupArchive archive;

  @override
  Widget build(BuildContext context) => _Guard(
    repository: repository,
    builder: (context) => _page(context, '本地存档详情', [
      _status(repository),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '${_time(archive.createdAt)}\n${archive.deviceName}\n${_size(_localBytes(repository, archive))}\n${_contents(archive)}',
        ),
      ),
      SelectableText(archive.fileName),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('backup_restore'),
        onPressed: repository.busy
            ? null
            : () => _restore(context, repository, archive),
        child: const Text('恢复此存档'),
      ),
      OutlinedButton(
        onPressed: repository.busy || repository.config == null
            ? null
            : () => _act(context, repository, () => repository.upload(archive)),
        child: const Text('上传到云端'),
      ),
      OutlinedButton(
        onPressed: repository.busy
            ? null
            : () => _act(
                context,
                repository,
                () => repository.exportFile(archive),
              ),
        child: const Text('导出文件'),
      ),
      TextButton(
        onPressed: repository.busy
            ? null
            : () async {
                if (!await _confirm(
                  context,
                  repository,
                  '删除本地存档？',
                  '只删除此存档，当前数据和云端副本均保留。',
                )) {
                  return;
                }
                if (!context.mounted) return;
                final done = await _act(context, repository, () async {
                  await repository.deleteLocal(archive);
                  return true;
                });
                if (done == true && context.mounted && !repository.isPrivate) {
                  Navigator.pop(context);
                }
              },
        child: const Text('删除存档'),
      ),
    ]),
  );
}

class _RemoteDetailScreen extends StatefulWidget {
  const _RemoteDetailScreen({required this.repository, required this.entry});
  final BackupRepository repository;
  final WebDavEntry entry;
  @override
  State<_RemoteDetailScreen> createState() => _RemoteDetailScreenState();
}

class _RemoteDetailScreenState extends State<_RemoteDetailScreen> {
  BackupArchive? _downloaded;
  @override
  Widget build(BuildContext context) {
    final repository = widget.repository, entry = widget.entry;
    return _Guard(
      repository: repository,
      builder: (context) => _page(context, '云端存档详情', [
        _status(repository),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(entry.name),
        ),
        Text(
          '云端修改时间：${_time(entry.modifiedAt)}\n${_size(entry.bytes)}\n内容：下载校验后查看',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('backup_download'),
          onPressed: repository.busy
              ? null
              : () async {
                  final archive = await _act(
                    context,
                    repository,
                    () => repository.download(entry),
                  );
                  if (archive != null && mounted && !repository.isPrivate) {
                    setState(() => _downloaded = archive);
                  }
                },
          icon: const Icon(Icons.download_outlined),
          label: const Text('下载到本地'),
        ),
        if (_downloaded case final archive?) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('下载完成，当前数据未改变'),
          ),
          OutlinedButton(
            onPressed: repository.busy
                ? null
                : () => _push(
                    context,
                    _LocalDetailScreen(
                      repository: repository,
                      archive: archive,
                    ),
                  ),
            child: const Text('查看本地存档'),
          ),
          OutlinedButton(
            onPressed: repository.busy
                ? null
                : () => _restore(context, repository, archive),
            child: const Text('恢复此存档'),
          ),
        ],
        TextButton(
          onPressed: repository.busy
              ? null
              : () => _act(
                  context,
                  repository,
                  () => repository.ignoreRemote(entry),
                ),
          child: const Text('忽略此存档的启动提醒'),
        ),
        TextButton(
          onPressed: repository.busy
              ? null
              : () async {
                  if (!await _confirm(
                    context,
                    repository,
                    '删除云端存档？',
                    '只删除此云端存档，本地副本和当前数据均保留。',
                  )) {
                    return;
                  }
                  if (!context.mounted) return;
                  final done = await _act(context, repository, () async {
                    await repository.deleteRemote(entry);
                    return true;
                  });
                  if (done == true &&
                      context.mounted &&
                      !repository.isPrivate) {
                    Navigator.pop(context);
                  }
                },
          child: const Text('删除云端存档'),
        ),
      ]),
    );
  }
}

class _RestoreScreen extends StatefulWidget {
  const _RestoreScreen({required this.repository, required this.archive});
  final BackupRepository repository;
  final BackupArchive archive;
  @override
  State<_RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<_RestoreScreen> {
  late final Set<String> _sections = {...widget.archive.data.keys};
  bool _replace = false, _preferArchive = false;
  RestorePreview? _preview;

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final theme = Theme.of(context);
    final preview = _preview;
    return _Guard(
      repository: repository,
      builder: (context) => PopScope(
        canPop: !repository.busy && preview == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !repository.busy) setState(() => _preview = null);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(preview == null ? '恢复选项' : '确认恢复'),
            leading: IconButton(
              tooltip: preview == null ? '取消' : '返回选项',
              icon: Icon(preview == null ? Icons.close : Icons.arrow_back),
              onPressed: repository.busy
                  ? null
                  : () {
                      if (preview == null) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _preview = null);
                      }
                    },
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey(
                      preview == null ? 'restore_options' : 'restore_results',
                    ),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        preview == null ? '第 1 步 · 选择恢复内容' : '第 2 步 · 核对恢复结果',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.archive.deviceName} · ${_time(widget.archive.createdAt)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (preview == null) ...[
                        _RestoreSection(
                          title: '恢复方式',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<bool>(
                                showSelectedIcon: false,
                                segments: const [
                                  ButtonSegment(
                                    value: false,
                                    label: Text(
                                      '合并',
                                      key: Key('restore_mode_merge'),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: true,
                                    label: Text(
                                      '覆盖',
                                      key: Key('restore_mode_replace'),
                                    ),
                                  ),
                                ],
                                selected: {_replace},
                                onSelectionChanged: repository.busy
                                    ? null
                                    : (value) => setState(
                                        () => _replace = value.single,
                                      ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _replace
                                    ? '用存档替换勾选内容；空收藏会清空当前收藏。'
                                    : '加入缺少的内容。不会同步删除，旧收藏可能重新加入。',
                              ),
                            ],
                          ),
                        ),
                        _RestoreSection(
                          title: '恢复内容',
                          child: Column(
                            children: [
                              for (final section in widget.archive.data.keys)
                                CheckboxListTile(
                                  key: Key('restore_section_$section'),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(_sectionNames[section]!),
                                  value: _sections.contains(section),
                                  onChanged: repository.busy
                                      ? null
                                      : (value) => setState(() {
                                          if (value == true) {
                                            _sections.add(section);
                                          } else {
                                            _sections.remove(section);
                                          }
                                        }),
                                ),
                            ],
                          ),
                        ),
                        if (!_replace)
                          _RestoreSection(
                            title: '冲突时采用',
                            child: RadioGroup<bool>(
                              groupValue: _preferArchive,
                              onChanged: (value) {
                                if (value != null && !repository.busy) {
                                  setState(() => _preferArchive = value);
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<bool>(
                                    contentPadding: EdgeInsets.zero,
                                    value: false,
                                    title: const Text('本机内容'),
                                    subtitle: const Text('保留本机条目和应用设置'),
                                    enabled: !repository.busy,
                                  ),
                                  RadioListTile<bool>(
                                    key: const Key('restore_prefer_archive'),
                                    contentPadding: EdgeInsets.zero,
                                    value: true,
                                    title: const Text('存档内容'),
                                    subtitle: const Text('冲突条目和应用设置采用存档值'),
                                    enabled: !repository.busy,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ] else ...[
                        Text(
                          preview.replace ? '覆盖所选内容' : '合并到当前数据',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        ..._summary(context, preview),
                        if (!preview.replace)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text('合并不会同步删除，旧收藏可能重新加入。'),
                          ),
                        _RestoreSection(
                          title: '自动保护',
                          child: const Text(
                            '恢复前先创建完整的本地安全存档，保存失败不会修改数据。\n\nPIN、隐私状态、WebDAV 凭据和下载文件均保留。',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (repository.busy) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: repository.busy
                              ? null
                              : () {
                                  if (preview == null) {
                                    Navigator.pop(context);
                                  } else {
                                    setState(() => _preview = null);
                                  }
                                },
                          child: Text(preview == null ? '取消' : '返回选项'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: Key(
                            preview == null
                                ? 'restore_preview'
                                : 'restore_confirm',
                          ),
                          onPressed:
                              repository.busy ||
                                  (preview == null && _sections.isEmpty)
                              ? null
                              : () async {
                                  if (preview == null) {
                                    final result = await _act(
                                      context,
                                      repository,
                                      () => repository.preview(
                                        widget.archive,
                                        replace: _replace,
                                        preferArchive: _preferArchive,
                                        sections: {..._sections},
                                      ),
                                    );
                                    if (result != null &&
                                        mounted &&
                                        !repository.isPrivate) {
                                      setState(() => _preview = result);
                                    }
                                  } else {
                                    final done = await _act(
                                      context,
                                      repository,
                                      () async {
                                        await repository.restore(preview);
                                        return true;
                                      },
                                    );
                                    if (done == true &&
                                        context.mounted &&
                                        !repository.isPrivate) {
                                      Navigator.pop(context);
                                    }
                                  }
                                },
                          child: Text(
                            preview == null ? '预览变更' : '确认恢复',
                            textAlign: TextAlign.center,
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
      ),
    );
  }
}

class _RestoreSection extends StatelessWidget {
  const _RestoreSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

List<Widget> _summary(BuildContext context, RestorePreview preview) {
  final result = <Widget>[];
  for (final section in preview.groups.keys) {
    final before = preview.before[section] ?? const <String, Object?>{};
    final after = preview.groups[section]!;
    if (section == 'favorites' || section == 'sources') {
      final key = section == 'favorites' ? 'items' : 'custom';
      final id = section == 'favorites' ? 'postId' : 'id';
      Map<String, Map> rows(Map<String, Object?> group) => {
        for (final row in group[key] as List? ?? const [])
          (row as Map)[id] as String: row,
      };
      final old = rows(before),
          next = rows(after),
          incoming = rows(preview.archive.data[section]!);
      final added = next.keys.where((id) => !old.containsKey(id)).length;
      final deleted = old.keys.where((id) => !next.containsKey(id)).length;
      final conflicts = incoming.keys
          .where((id) => old.containsKey(id) && !_same(old[id], incoming[id]))
          .length;
      result.add(
        _RestoreSection(
          title: _sectionNames[section]!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '恢复后 ${next.length} 条',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [Text('新增 $added'), Text('冲突 $conflicts')],
              ),
              if (preview.replace && deleted > 0) ...[
                const SizedBox(height: 12),
                Text(
                  section == 'favorites'
                      ? '将删除 $deleted 条收藏'
                      : '将删除 $deleted 个自定义源',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      );
    } else {
      final adopt =
          preview.replace ||
          preview.preferArchive ||
          !preview.before.containsKey(section);
      result.add(
        _RestoreSection(
          title: _sectionNames[section]!,
          child: Text(adopt ? '采用存档设置' : '保持本机设置不变'),
        ),
      );
    }
  }
  return result;
}

bool _same(Object? a, Object? b) {
  Object? stable(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: stable(value[key])};
    }
    if (value is List) return value.map(stable).toList();
    return value;
  }

  return jsonEncode(stable(a)) == jsonEncode(stable(b));
}

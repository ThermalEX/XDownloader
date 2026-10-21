import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import 'sources_screen.dart';
import 'naming_settings_screen.dart';

class RuleSettingsScreen extends StatelessWidget {
  const RuleSettingsScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('规则设置')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          dependencies.sources,
          dependencies.settings,
        ]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名规则'),
                subtitle: Text(
                  dependencies.settings.value.useOriginalFileName
                      ? '原始标题'
                      : dependencies.settings.value.fileNameTemplate,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NamingSettingsScreen(repository: dependencies.settings),
                  ),
                ),
              ),
              ListTile(
                title: const Text('下载源'),
                leading: const Icon(Icons.dns_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SourcesScreen(
                      repository: dependencies.sources,
                      parser: dependencies.parser,
                      readClipboard: dependencies.readClipboard,
                    ),
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

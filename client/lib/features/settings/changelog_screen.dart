import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/update_repository.dart';
import 'release_notes.dart';
import 'settings_group.dart';

class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key, required this.updates});
  final UpdateRepository updates;
  @override
  State<ChangelogScreen> createState() => _ChangelogState();
}

class _ChangelogState extends State<ChangelogScreen> {
  late final _notes = rootBundle.loadString('assets/CHANGELOG.md');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('更新日志')),
    body: SafeArea(
      child: FutureBuilder<String>(
        future: _notes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('暂时无法读取更新日志'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SettingsPanel(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ReleaseNotes(
                    data: snapshot.data!,
                    onOpenLink: (uri) => widget.updates.openPage(uri),
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

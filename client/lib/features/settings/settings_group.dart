import 'package:flutter/material.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
          ),
        ),
        for (var i = 0; i < children.length; i++)
          SettingsPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: children[i],
            ),
          ),
      ],
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, this.title, required this.child});
  final String? title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: const EdgeInsets.only(bottom: 16),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colors.primary),
                ),
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
          ],
          child,
        ],
      ),
    );
  }
}

class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key});
  final IconData icon;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 24,
    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
    child: Icon(icon),
  );
}

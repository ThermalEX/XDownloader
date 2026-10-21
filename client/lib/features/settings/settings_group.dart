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
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(i == 0 ? 28 : 12),
                bottom: Radius.circular(i == children.length - 1 ? 28 : 12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: children[i],
              ),
            ),
          ),
      ],
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

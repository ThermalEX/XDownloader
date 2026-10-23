import 'dart:math' as math;

import 'package:flutter/material.dart';

// Reserve two lines for both one-line and two-line settings rows.
// Scale each theme style separately to support nonlinear accessibility scaling.
double settingsRowHeight(BuildContext context) {
  final textTheme = Theme.of(context).textTheme;
  final titleStyle = textTheme.titleMedium!;
  final subtitleStyle = textTheme.bodyMedium!;
  final scaler = MediaQuery.textScalerOf(context);
  return math.max(
    72.0,
    scaler.scale(titleStyle.fontSize!) * (titleStyle.height ?? 1.5) +
        scaler.scale(subtitleStyle.fontSize!) * (subtitleStyle.height ?? 1.5) +
        16,
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.grouped = false,
  });
  final String title;
  final List<Widget> children;
  final bool grouped;

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
          if (grouped)
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
            )
          else
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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

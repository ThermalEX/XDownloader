import 'package:flutter/material.dart';

import '../core/models/app_settings.dart';

/// Action placement only; language direction and settings layouts stay intact.
class HandedLayout extends InheritedWidget {
  const HandedLayout({
    super.key,
    required this.handedness,
    required super.child,
  });
  final Handedness handedness;

  static bool isLeft(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HandedLayout>()?.handedness ==
      Handedness.left;
  static TextDirection rowDirection(BuildContext context) =>
      isLeft(context) ? TextDirection.rtl : TextDirection.ltr;
  static Alignment actionAlignment(BuildContext context) =>
      isLeft(context) ? Alignment.centerLeft : Alignment.centerRight;
  static MainAxisAlignment dialogAlignment(BuildContext context) =>
      isLeft(context) ? MainAxisAlignment.start : MainAxisAlignment.end;
  static List<Widget> actions(BuildContext context, List<Widget> widgets) =>
      isLeft(context) ? widgets.reversed.toList(growable: false) : widgets;

  @override
  bool updateShouldNotify(HandedLayout oldWidget) =>
      handedness != oldWidget.handedness;
}

class HandedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HandedAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.enabled = true,
  });
  final Widget title;
  final List<Widget> actions;
  final bool enabled;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final left = enabled && HandedLayout.isLeft(context) && actions.isNotEmpty;
    return AppBar(
      title: left
          ? Row(
              children: [
                ...actions.reversed,
                const SizedBox(width: 8),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: title),
                ),
              ],
            )
          : title,
      actions: left ? null : actions,
    );
  }
}

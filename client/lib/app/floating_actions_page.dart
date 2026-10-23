import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps the scroll viewport behind its bottom actions, without painting a panel.
class FloatingActionsPage extends StatelessWidget {
  const FloatingActionsPage({
    super.key,
    required this.content,
    required this.actions,
    this.fadeKey,
  });

  final Widget content;
  final Widget actions;
  final Key? fadeKey;

  /// Scrollable content adds this to its normal bottom padding so its last item
  /// can move completely above the measured actions, including enlarged text.
  static double bottomInsetOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ActionsInset>()?.bottom ?? 0;

  @override
  Widget build(BuildContext context) => _FloatingActionsLayout(
    actions: actions,
    content: LayoutBuilder(
      builder: (context, constraints) {
        final measured = constraints as _ContentConstraints;
        final start = measured.fadeStart;
        return _ActionsInset(
          bottom: measured.bottomInset,
          child: ShaderMask(
            key: fadeKey,
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.white, Colors.white, Colors.transparent],
              stops: [
                0,
                bounds.height > 0 ? (start / bounds.height).clamp(0, 1) : 1,
                1,
              ],
            ).createShader(bounds),
            child: content,
          ),
        );
      },
    ),
  );
}

/// Marks the real input/button row, excluding a separate favorite button or
/// outside padding. The content fade begins halfway down this measured row.
class FloatingActionAnchor extends SingleChildRenderObjectWidget {
  const FloatingActionAnchor({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _ActionAnchorBox();
}

class _ActionAnchorBox extends RenderProxyBox {
  double midpoint = 0;

  @override
  void performLayout() {
    super.performLayout();
    midpoint = size.height / 2;
  }
}

class _ActionsInset extends InheritedWidget {
  const _ActionsInset({required this.bottom, required super.child});
  final double bottom;

  @override
  bool updateShouldNotify(_ActionsInset oldWidget) =>
      bottom != oldWidget.bottom;
}

// Extra constraint values make LayoutBuilder run again when actions resize,
// while the content itself still receives a tight, full-height viewport.
class _ContentConstraints extends BoxConstraints {
  _ContentConstraints(super.size, this.bottomInset, this.fadeStart)
    : super.tight();

  final double bottomInset;
  final double fadeStart;

  @override
  bool operator ==(Object other) =>
      other is _ContentConstraints &&
      super == other &&
      bottomInset == other.bottomInset &&
      fadeStart == other.fadeStart;

  @override
  int get hashCode => Object.hash(super.hashCode, bottomInset, fadeStart);
}

class _FloatingActionsLayout extends MultiChildRenderObjectWidget {
  _FloatingActionsLayout({required Widget content, required Widget actions})
    : super(children: [content, actions]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _FloatingActionsBox();
}

class _FloatingActionsParentData extends ContainerBoxParentData<RenderBox> {}

class _FloatingActionsBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FloatingActionsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FloatingActionsParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FloatingActionsParentData) {
      child.parentData = _FloatingActionsParentData();
    }
  }

  _ActionAnchorBox? _findAnchor(RenderObject object) {
    if (object is _ActionAnchorBox) return object;
    _ActionAnchorBox? anchor;
    object.visitChildren((child) => anchor ??= _findAnchor(child));
    return anchor;
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final content = firstChild!;
    final actions = lastChild!;
    actions.layout(
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
      parentUsesSize: true,
    );
    final actionsTop = size.height - actions.size.height;
    (actions.parentData! as _FloatingActionsParentData).offset = Offset(
      0,
      actionsTop,
    );
    final anchor = _findAnchor(actions);
    final center = anchor?.localToGlobal(
      Offset(0, anchor.midpoint),
      ancestor: actions,
    );
    content.layout(
      _ContentConstraints(
        size,
        actions.size.height,
        actionsTop + (center?.dy ?? actions.size.height / 2),
      ),
      parentUsesSize: true,
    );
    (content.parentData! as _FloatingActionsParentData).offset = Offset.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

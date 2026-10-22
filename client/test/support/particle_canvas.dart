import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records drawing output for geometry regressions and targeted probe captures.
class ParticleCanvas extends Fake implements Canvas {
  Offset center = Offset.zero;
  final positions = <Offset>[];
  final scales = <double>[];
  final rotations = <double>[];
  final colors = <Color>{};
  final styles = <PaintingStyle>{};
  int paragraphs = 0;
  int tremblingMarks = 0;
  @override
  void save() {}
  @override
  void restore() {}
  @override
  void translate(double dx, double dy) => positions.add(Offset(dx, dy));
  @override
  void rotate(double radians) => rotations.add(radians);
  @override
  void scale(double sx, [double? sy]) => scales.add(sx);
  @override
  void drawPath(Path path, Paint paint) {
    colors.add(paint.color);
    styles.add(paint.style);
    // Hearts are closed; their tiny highlight is short. Tremble glyphs are
    // extended open zigzags/curves, so outlines/highlights cannot satisfy this.
    if (paint.style == PaintingStyle.stroke &&
        path.getBounds().height > 12 &&
        path.computeMetrics().any((m) => !m.isClosed && m.length > 20)) {
      tremblingMarks++;
    }
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;
}

ParticleCanvas snapshotParticles(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (w) =>
        w is CustomPaint &&
        (w.key == const Key('avatar_anger_burst') ||
            w.key == const Key('avatar_heart_burst')),
  );
  final canvas = ParticleCanvas();
  final size = tester.getSize(finder.last);
  canvas.center = size.center(Offset.zero);
  tester.widget<CustomPaint>(finder.last).painter!.paint(canvas, size);
  return canvas;
}

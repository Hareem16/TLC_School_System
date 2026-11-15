import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/academic/result_graph_colors.dart';

void main() {
  test(
    'equal marks share a color while different marks get distinct colors',
    () {
      final marks = List<double>.generate(36, (index) => index.toDouble());
      final colors = subjectGraphColorsForMarks([...marks, 12, 35]);

      expect(colors[12], colors[36]);
      expect(colors[35], colors[37]);
      expect(
        colors.take(36).map((color) => color.toARGB32()).toSet(),
        hasLength(36),
      );
    },
  );

  test('graph colors avoid red and green hues', () {
    final colors = subjectGraphColorsForMarks(
      List<double>.generate(36, (index) => index.toDouble()),
    );

    for (final color in colors) {
      final hue = HSLColor.fromColor(color).hue;
      expect(hue < 20 || hue > 340, isFalse);
      expect(hue >= 80 && hue <= 160, isFalse);
    }
  });
}

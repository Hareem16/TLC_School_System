import 'package:flutter/material.dart';

List<Color> subjectGraphColorsForMarks(List<double> marks) {
  const hues = [
    42.0,
    210.0,
    290.0,
    58.0,
    238.0,
    310.0,
    34.0,
    188.0,
    276.0,
    62.0,
    224.0,
    300.0,
    48.0,
    252.0,
    284.0,
    36.0,
    198.0,
    318.0,
  ];
  const saturations = [0.72, 0.88, 0.64];
  const lightnesses = [0.45, 0.56, 0.35];
  final colorByMark = <String, Color>{};

  return marks
      .map((mark) {
        final key = (mark * 100).round().toString();
        return colorByMark.putIfAbsent(key, () {
          final colorIndex = colorByMark.length;
          final variant = colorIndex ~/ hues.length;
          return HSLColor.fromAHSL(
            1,
            hues[colorIndex % hues.length],
            saturations[variant % saturations.length],
            lightnesses[(variant ~/ saturations.length) % lightnesses.length],
          ).toColor();
        });
      })
      .toList(growable: false);
}

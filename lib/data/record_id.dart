import 'dart:math';

String newRecordId() => List<int>.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

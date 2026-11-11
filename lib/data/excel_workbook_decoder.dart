import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

class ExcelWorkbookDecoder {
  static Excel decode(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final stylesIndex = archive.files.indexWhere(
      (file) => file.name == 'xl/styles.xml',
    );
    if (stylesIndex == -1) return Excel.decodeBytes(bytes);

    final stylesFile = archive.files[stylesIndex];
    final stylesXml = utf8.decode(stylesFile.content as List<int>);
    final numFormatTags = RegExp(
      r'<numFmt\b[^>]*numFmtId="(\d+)"[^>]*/>',
    );
    final existingCustomIds = numFormatTags
        .allMatches(stylesXml)
        .map((match) => int.parse(match[1]!))
        .where((id) => id >= 164);
    var nextCustomId =
        (existingCustomIds.isEmpty ? 163 : existingCustomIds.reduce(
          (left, right) => left > right ? left : right,
        )) +
        1;
    final remappedIds = <String, String>{};
    var normalizedStyles = stylesXml.replaceAllMapped(numFormatTags, (match) {
      final id = int.parse(match[1]!);
      if (id >= 164) return match[0]!;
      final replacement = (nextCustomId++).toString();
      remappedIds[match[1]!] = replacement;
      return match[0]!.replaceFirst('numFmtId="${match[1]}"', 'numFmtId="$replacement"');
    });
    for (final entry in remappedIds.entries) {
      normalizedStyles = normalizedStyles.replaceAllMapped(
        RegExp('<xf\\b[^>]*numFmtId="${entry.key}"[^>]*>'),
        (match) => match[0]!.replaceFirst(
          'numFmtId="${entry.key}"',
          'numFmtId="${entry.value}"',
        ),
      );
    }
    if (normalizedStyles == stylesXml) return Excel.decodeBytes(bytes);

    archive[stylesIndex] = ArchiveFile(
      stylesFile.name,
      utf8.encode(normalizedStyles).length,
      Uint8List.fromList(utf8.encode(normalizedStyles)),
    );
    final normalizedBytes = ZipEncoder().encode(archive);
    if (normalizedBytes == null) {
      throw const FormatException(
        'The Excel workbook could not be normalized.',
      );
    }
    return Excel.decodeBytes(normalizedBytes);
  }
}

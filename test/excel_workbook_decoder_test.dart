import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/excel_workbook_decoder.dart';

void main() {
  test('normalizes a built-in number format embedded as a custom format', () {
    final workbook = Excel.createExcel();
    workbook['Sheet1'].appendRow([TextCellValue('TLC')]);
    final archive = ZipDecoder().decodeBytes(workbook.encode()!);
    final styles = archive.findFile('xl/styles.xml')!;
    var xml = utf8.decode(styles.content as List<int>);

    final numFmts = RegExp(r'<numFmts\b[^>]*>.*?</numFmts>');
    final existingNumFmts = numFmts.firstMatch(xml);
    if (existingNumFmts == null) {
      xml = xml.replaceFirst(
        '</styleSheet>',
        '<numFmts count="1"><numFmt numFmtId="43" formatCode="#,##0.00"/></numFmts></styleSheet>',
      );
    } else {
      xml = xml.replaceFirst(
        existingNumFmts[0]!,
        '<numFmts count="1"><numFmt numFmtId="43" formatCode="#,##0.00"/></numFmts>',
      );
    }
    final cellXfsStart = xml.indexOf('<cellXfs');
    final cellXfsEnd = xml.indexOf('</cellXfs>');
    final cellXfs = xml.substring(cellXfsStart, cellXfsEnd);
    final originalXf = RegExp(r'<xf\b[^>]*numFmtId="0"[^>]*>')
        .firstMatch(cellXfs)!
        .group(0)!;
    final updatedXf = originalXf.replaceFirst('numFmtId="0"', 'numFmtId="43"');
    xml = xml.replaceFirst(originalXf, updatedXf);
    archive.addFile(
      ArchiveFile(
        styles.name,
        utf8.encode(xml).length,
        Uint8List.fromList(utf8.encode(xml)),
      ),
    );
    final malformedBytes = ZipEncoder().encode(archive)!;

    final decoded = ExcelWorkbookDecoder.decode(malformedBytes);

    expect(decoded.tables['Sheet1']!.rows.first.first!.value, isA<TextCellValue>());
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import 'fee_repository.dart';

class FeeExcelExporter {
  static const _columnCount = 19;
  static const _headers = [
    'Date',
    'Receipt No (Voucher No.)',
    'Student Name',
    'Class',
    'Details (Month/s)',
    'Fees',
    'Annual',
    'Admission',
    'Lab',
    'Copies',
    'Stationery',
    'Extras',
    'LPC',
    'Arrears',
    'Total Payable',
    'Amount Paid',
    'Outstanding',
    'Payment Status',
    'Remarks',
  ];

  static Uint8List encode(
    Iterable<FeeCharge> charges, {
    String title = 'TLC FEES AND VOUCHERS',
    String emptyMessage = 'No fee records matched the selected filters.',
  }) {
    final chargeList = charges.toList(growable: false);
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'Fee Ledger');
    final sheet = workbook['Fee Ledger'];
    sheet.appendRow([TextCellValue(title)]);
    sheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('S1'),
      customValue: TextCellValue(title),
    );
    sheet.cell(CellIndex.indexByString('A1')).cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      topBorder: _border(BorderStyle.Medium),
      bottomBorder: _border(BorderStyle.Medium),
      leftBorder: _border(BorderStyle.Medium),
      rightBorder: _border(BorderStyle.Medium),
    );
    sheet.setRowHeight(0, 30);

    sheet.appendRow(_headers.map(TextCellValue.new).toList());

    for (final charge in chargeList) {
      final arrearsDetails = charge.arrears
          .map(
            (arrears) =>
                '${arrears.monthKey}: '
                'PKR ${arrears.balance.toStringAsFixed(2)}',
          )
          .join(', ');
      final remarks = [
        if (charge.remarks.trim().isNotEmpty) charge.remarks.trim(),
        if (arrearsDetails.isNotEmpty) 'Arrears: $arrearsDetails',
        if (charge.totalOutstanding == 0)
          'Paid in full'
        else
          '${charge.status}; PKR '
              '${charge.totalOutstanding.toStringAsFixed(2)} outstanding',
      ].join('; ');
      sheet.appendRow(
        [
          charge.createdAt?.toIso8601String().split('T').first ?? '',
          charge.voucherNumber,
          charge.studentName,
          charge.className,
          charge.detailsMonths,
          charge.fees,
          charge.annual,
          charge.admission,
          charge.lab,
          charge.copies,
          charge.stationery,
          charge.extras,
          charge.lpc,
          charge.arrearsBalance,
          charge.totalPayable,
          charge.amountPaid,
          charge.totalOutstanding,
          charge.status == 'Partial' ? 'Partial Paid' : charge.status,
          remarks,
        ].asMap().entries.map((entry) {
          final value = entry.value;
          if (entry.key >= 5 && entry.key <= 16 && value is double) {
            return DoubleCellValue(value);
          }
          return TextCellValue(value.toString());
        }).toList(),
      );
    }

    final lastDataRow = chargeList.length + 2;
    if (chargeList.isNotEmpty) {
      final totals = List<CellValue?>.filled(_columnCount, null);
      totals[0] = TextCellValue('TOTAL');
      for (var column = 5; column <= 16; column++) {
        final columnName = _columnName(column);
        totals[column] = FormulaCellValue(
          'SUM($columnName'
          '3:$columnName$lastDataRow)',
        );
      }
      sheet.appendRow(totals);
    } else {
      sheet.merge(
        CellIndex.indexByString('A3'),
        CellIndex.indexByString('S3'),
        customValue: TextCellValue(emptyMessage),
      );
      sheet.cell(CellIndex.indexByString('A3')).cellStyle = CellStyle(
        italic: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        topBorder: _border(BorderStyle.Thin),
        bottomBorder: _border(BorderStyle.Thin),
        leftBorder: _border(BorderStyle.Thin),
        rightBorder: _border(BorderStyle.Thin),
      );
    }

    _formatTable(sheet, chargeList, lastDataRow);

    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('The fee ledger workbook could not be encoded.');
    }
    return _addAutoFilter(bytes, lastDataRow);
  }

  static void _formatTable(
    Sheet sheet,
    List<FeeCharge> charges,
    int lastDataRow,
  ) {
    const headerRow = 1;
    final thinBorder = _border(BorderStyle.Thin);
    final mediumBorder = _border(BorderStyle.Medium);
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('FF24476B'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      topBorder: mediumBorder,
      bottomBorder: mediumBorder,
      leftBorder: thinBorder,
      rightBorder: thinBorder,
    );
    sheet.setRowHeight(headerRow, 32);

    for (var column = 0; column < _columnCount; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(
                  columnIndex: column,
                  rowIndex: headerRow,
                ),
              )
              .cellStyle =
          headerStyle;
      sheet.setColumnAutoFit(column);
    }

    final lastTableRow = charges.isEmpty ? headerRow : lastDataRow;
    for (var row = headerRow; row <= lastTableRow; row++) {
      for (var column = 0; column < _columnCount; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
        );
        final baseStyle = cell.cellStyle ?? CellStyle();
        cell.cellStyle = baseStyle.copyWith(
          leftBorderVal: column == 0 ? mediumBorder : thinBorder,
          rightBorderVal: column == _columnCount - 1
              ? mediumBorder
              : thinBorder,
          topBorderVal: row == headerRow ? mediumBorder : thinBorder,
          bottomBorderVal: row == lastTableRow ? mediumBorder : thinBorder,
          numberFormat: column >= 5 && column <= 16
              ? NumFormat.standard_2
              : null,
          textWrappingVal: column == 4 || column == 18
              ? TextWrapping.WrapText
              : null,
        );
      }
    }

    if (charges.isNotEmpty) {
      final totalsRow = lastDataRow;
      for (var column = 0; column < _columnCount; column++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: totalsRow),
        );
        final baseStyle = cell.cellStyle ?? CellStyle();
        cell.cellStyle = baseStyle.copyWith(
          boldVal: true,
          backgroundColorHexVal: ExcelColor.fromHexString('FFE8EEF4'),
          topBorderVal: mediumBorder,
          bottomBorderVal: mediumBorder,
          leftBorderVal: column == 0 ? mediumBorder : thinBorder,
          rightBorderVal: column == _columnCount - 1
              ? mediumBorder
              : thinBorder,
        );
      }
    }

    final firstColumnWidth = _columnWidth([
      _headers.first,
      ...charges.map(
        (charge) => charge.createdAt?.toIso8601String().split('T').first ?? '',
      ),
    ], maximum: 24);
    sheet.setColumnWidth(0, firstColumnWidth);
    sheet.setColumnWidth(
      _columnCount - 1,
      _columnWidth([
        _headers.last,
        ...charges.map((charge) => charge.remarks),
      ], maximum: 42),
    );
  }

  static Border _border(BorderStyle style) =>
      Border(borderStyle: style, borderColorHex: ExcelColor.black);

  static double _columnWidth(Iterable<String> values, {required int maximum}) {
    final characters = values.fold<int>(
      0,
      (longest, value) => value.length > longest ? value.length : longest,
    );
    return ((characters.clamp(8, maximum) * 7.0 + 9.0) / 7.0 * 256).truncate() /
        256;
  }

  static Uint8List _addAutoFilter(List<int> bytes, int lastDataRow) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final worksheet = archive.findFile('xl/worksheets/sheet1.xml');
    if (worksheet == null) {
      throw StateError('The fee ledger worksheet could not be found.');
    }

    final xml = utf8.decode(worksheet.content as List<int>);
    final mergeCellsMarker = xml.indexOf('<mergeCells');
    final pageMarginsMarker = xml.indexOf('<pageMargins');
    final closingTag = xml.indexOf('</worksheet>');
    final insertAt = mergeCellsMarker >= 0
        ? mergeCellsMarker
        : pageMarginsMarker >= 0
        ? pageMarginsMarker
        : closingTag;
    if (insertAt < 0) {
      throw StateError('The fee ledger worksheet XML is invalid.');
    }
    final updatedXml = xml.replaceRange(
      insertAt,
      insertAt,
      '<autoFilter ref="A2:S$lastDataRow"/>',
    );
    final updatedBytes = utf8.encode(updatedXml);
    archive.addFile(
      ArchiveFile(
        'xl/worksheets/sheet1.xml',
        updatedBytes.length,
        updatedBytes,
      ),
    );

    final encoded = ZipEncoder().encode(archive);
    if (encoded == null) {
      throw StateError('The fee ledger filters could not be encoded.');
    }
    return Uint8List.fromList(encoded);
  }

  static String _columnName(int columnIndex) {
    var value = columnIndex + 1;
    var name = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      name = String.fromCharCode(65 + remainder) + name;
      value = (value - 1) ~/ 26;
    }
    return name;
  }
}

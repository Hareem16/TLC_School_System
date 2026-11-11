import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'inventory_repository.dart';

class InventoryExcelExporter {
  static const _headers = [
    'Item Name',
    'Category',
    'Unit',
    'Reorder Level',
    'Opening Quantity',
    'Unit Cost',
    'Supplier',
    'Reference',
    'Notes',
  ];

  static Uint8List encode(Iterable<InventoryItem> items) {
    final workbook = Excel.createExcel();
    final sheet = workbook['Inventory'];
    sheet.appendRow(
      [
        'Item Name',
        'Category',
        'Unit',
        'Quantity On Hand',
        'Reorder Level',
        'Notes',
      ].map(TextCellValue.new).toList(),
    );
    for (final item in items) {
      sheet.appendRow(
        [
          item.name,
          item.category,
          item.unit,
          item.quantityOnHand.toStringAsFixed(2),
          item.reorderLevel.toStringAsFixed(2),
          item.notes,
        ].map(TextCellValue.new).toList(),
      );
    }
    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('The inventory workbook could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  }

  static Uint8List encodeImportTemplate() {
    final workbook = Excel.createExcel();
    workbook['Inventory Import'].appendRow(
      _headers.map(TextCellValue.new).toList(),
    );
    final bytes = workbook.encode();
    if (bytes == null) {
      throw StateError('The inventory import template could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  }
}

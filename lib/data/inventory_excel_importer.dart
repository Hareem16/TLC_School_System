import 'package:excel/excel.dart';

import 'excel_workbook_decoder.dart';
import 'inventory_repository.dart';

class InventoryExcelImportResult {
  final List<InventoryImportItem> items;
  final int skippedBlankRows;
  final List<String> errors;

  const InventoryExcelImportResult({
    required this.items,
    required this.skippedBlankRows,
    required this.errors,
  });
}

class InventoryExcelImporter {
  InventoryExcelImportResult parse(List<int> bytes) {
    final workbook = ExcelWorkbookDecoder.decode(bytes);
    if (workbook.tables.isEmpty) {
      throw const FormatException('The workbook does not contain a worksheet.');
    }
    final requiredColumns = {
      'itemname': 'Item Name',
      'category': 'Category',
      'unit': 'Unit',
      'reorderlevel': 'Reorder Level',
      'openingquantity': 'Opening Quantity',
      'unitcost': 'Unit Cost',
    };
    Sheet? sheet;
    Map<String, int>? headers;
    for (final candidate in workbook.tables.values) {
      if (candidate.rows.isEmpty) continue;
      final candidateHeaders = <String, int>{};
      for (var column = 0; column < candidate.rows.first.length; column++) {
        final key = _normalize(_cellText(candidate.rows.first[column]));
        if (key.isNotEmpty) candidateHeaders[key] = column;
      }
      if (requiredColumns.keys.every(candidateHeaders.containsKey)) {
        sheet = candidate;
        headers = candidateHeaders;
        break;
      }
    }
    if (sheet == null || headers == null) {
      throw FormatException(
        'No worksheet has all required inventory headings: '
        '${requiredColumns.values.join(', ')}.',
      );
    }

    final items = <InventoryImportItem>[];
    final errors = <String>[];
    final seenItems = <String, int>{};
    var skippedBlankRows = 0;

    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final name = _value(row, headers['itemname']);
      final category = _value(row, headers['category']);
      final unit = _value(row, headers['unit']);
      final reorderText = _value(row, headers['reorderlevel']);
      final quantityText = _value(row, headers['openingquantity']);
      final costText = _value(row, headers['unitcost']);
      final worksheetRow = rowIndex + 1;

      if ([
        name,
        category,
        unit,
        reorderText,
        quantityText,
        costText,
      ].every((value) => value.isEmpty)) {
        skippedBlankRows++;
        continue;
      }
      if (name.isEmpty || category.isEmpty) {
        errors.add(
          'Row $worksheetRow is missing an item name or category.',
        );
        continue;
      }
      final reorderLevel = _optionalNumber(reorderText);
      final openingQuantity = _optionalNumber(quantityText);
      final unitCost = _optionalNumber(costText);
      if ((reorderText.isNotEmpty && reorderLevel == null) ||
          (quantityText.isNotEmpty && openingQuantity == null) ||
          (costText.isNotEmpty && unitCost == null)) {
        errors.add(
          'Row $worksheetRow contains an invalid reorder level, opening quantity, or unit cost.',
        );
        continue;
      }
      if ((reorderLevel != null && reorderLevel < 0) ||
          (openingQuantity != null && openingQuantity < 0) ||
          (unitCost != null && unitCost < 0)) {
        errors.add('Row $worksheetRow contains a negative quantity or cost.');
        continue;
      }

      final duplicateKey =
          '${name.toLowerCase()}\u001f${category.toLowerCase()}';
      final firstRow = seenItems.putIfAbsent(duplicateKey, () => worksheetRow);
      if (firstRow != worksheetRow) {
        errors.add(
          'Rows $firstRow and $worksheetRow contain the same item and category.',
        );
        continue;
      }

      items.add(
        InventoryImportItem(
          name: name,
          category: category,
          unit: unit,
          reorderLevel: reorderLevel,
          openingQuantity: openingQuantity,
          unitCost: unitCost,
          supplier: _value(row, headers['supplier']),
          reference: _value(row, headers['reference']),
          notes: _value(row, headers['notes']),
        ),
      );
    }

    return InventoryExcelImportResult(
      items: items,
      skippedBlankRows: skippedBlankRows,
      errors: errors,
    );
  }

  String _value(List<Data?> row, int? column) =>
      column == null || column >= row.length ? '' : _cellText(row[column]);

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    return value.toString().trim();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  double? _optionalNumber(String value) =>
      value.isEmpty ? null : double.tryParse(value);
}

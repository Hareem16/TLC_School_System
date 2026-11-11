import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/inventory_excel_importer.dart';

void main() {
  test('parses an inventory opening-stock workbook', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Inventory'];
    sheet.appendRow(
      [
        'Item Name',
        'Category',
        'Unit',
        'Reorder Level',
        'Opening Quantity',
        'Unit Cost',
        'Supplier',
        'Reference',
        'Notes',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow(
      [
        'Printer paper',
        'Stationery',
        'ream',
        '4',
        '12',
        '650',
        'School supplier',
        'INV-100',
        'Store room',
      ].map(TextCellValue.new).toList(),
    );

    final result = InventoryExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.items, hasLength(1));
    expect(result.items.single.name, 'Printer paper');
    expect(result.items.single.openingQuantity, 12);
    expect(result.items.single.unitCost, 650);
    expect(result.items.single.supplier, 'School supplier');
  });

  test('rejects duplicate item/category rows before importing', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow(
      [
        'Item Name',
        'Category',
        'Unit',
        'Reorder Level',
        'Opening Quantity',
        'Unit Cost',
      ].map(TextCellValue.new).toList(),
    );
    for (var index = 0; index < 2; index++) {
      sheet.appendRow(
        [
          'Printer paper',
          'Stationery',
          'ream',
          '4',
          '12',
          '650',
        ].map(TextCellValue.new).toList(),
      );
    }

    final result = InventoryExcelImporter().parse(workbook.encode()!);

    expect(result.items, hasLength(1));
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('same item and category'));
  });

  test('allows blank optional values for matching-item re-imports', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow(
      [
        'Item Name',
        'Category',
        'Unit',
        'Reorder Level',
        'Opening Quantity',
        'Unit Cost',
        'Notes',
      ].map(TextCellValue.new).toList(),
    );
    sheet.appendRow([
      TextCellValue('Printer paper'),
      TextCellValue('Stationery'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);

    final result = InventoryExcelImporter().parse(workbook.encode()!);

    expect(result.errors, isEmpty);
    expect(result.items.single.unit, isEmpty);
    expect(result.items.single.reorderLevel, isNull);
    expect(result.items.single.openingQuantity, isNull);
    expect(result.items.single.unitCost, isNull);
  });
}

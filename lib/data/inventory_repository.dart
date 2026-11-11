import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';
import 'record_id.dart';

class InventoryItem {
  final String id;
  final String name;
  final String category;
  final String unit;
  final double reorderLevel;
  final double quantityOnHand;
  final String notes;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.reorderLevel,
    required this.quantityOnHand,
    required this.notes,
  });

  bool get isLowStock => quantityOnHand <= reorderLevel;

  factory InventoryItem.fromDatabaseMap(Map<String, Object?> row) =>
      InventoryItem(
        id: row['item_id']! as String,
        name: row['item_name']! as String,
        category: row['category']! as String,
        unit: row['unit']! as String,
        reorderLevel: (row['reorder_level']! as num).toDouble(),
        quantityOnHand: (row['quantity_on_hand']! as num).toDouble(),
        notes: row['notes']! as String,
      );
}

class InventoryMovement {
  final String direction;
  final double quantity;
  final double unitCost;
  final String supplier;
  final String reference;
  final String notes;
  final DateTime movedAt;

  const InventoryMovement({
    required this.direction,
    required this.quantity,
    required this.unitCost,
    required this.supplier,
    required this.reference,
    required this.notes,
    required this.movedAt,
  });

  factory InventoryMovement.fromDatabaseMap(Map<String, Object?> row) =>
      InventoryMovement(
        direction: row['direction']! as String,
        quantity: (row['quantity']! as num).toDouble(),
        unitCost: (row['unit_cost']! as num).toDouble(),
        supplier: row['supplier']! as String,
        reference: row['reference']! as String,
        notes: row['notes']! as String,
        movedAt: DateTime.parse(row['moved_at']! as String),
      );
}

class InventoryImportItem {
  final String name;
  final String category;
  final String unit;
  final double? reorderLevel;
  final double? openingQuantity;
  final double? unitCost;
  final String supplier;
  final String reference;
  final String notes;

  const InventoryImportItem({
    required this.name,
    required this.category,
    required this.unit,
    required this.reorderLevel,
    required this.openingQuantity,
    required this.unitCost,
    required this.supplier,
    required this.reference,
    required this.notes,
  });
}

class InventoryImportCounts {
  final int imported;
  final int updated;
  final int unchanged;

  const InventoryImportCounts({
    required this.imported,
    required this.updated,
    required this.unchanged,
  });
}

class InventoryRepository {
  final AppDatabase _database;

  InventoryRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  Future<List<InventoryItem>> getItems({String search = ''}) async {
    final database = await _database.database;
    final query = '%${search.trim()}%';
    final rows = await database.rawQuery(
      '''
      SELECT i.item_id, i.item_name, i.category, i.unit, i.reorder_level, i.notes,
             COALESCE(SUM(
               CASE WHEN m.direction = 'in' THEN m.quantity ELSE -m.quantity END
             ), 0) AS quantity_on_hand
      FROM inventory_items i
      LEFT JOIN inventory_movements m ON m.item_id = i.item_id
      WHERE ? = '%%' OR i.item_name LIKE ? OR i.category LIKE ?
      GROUP BY i.item_id
      ORDER BY i.category COLLATE NOCASE, i.item_name COLLATE NOCASE
      ''',
      [query, query, query],
    );
    return rows.map(InventoryItem.fromDatabaseMap).toList(growable: false);
  }

  Future<void> saveItem({
    String? id,
    required String name,
    required String category,
    required String unit,
    required double reorderLevel,
    required String notes,
  }) async {
    if (name.trim().isEmpty || category.trim().isEmpty || unit.trim().isEmpty) {
      throw ArgumentError('Item name, category, and unit are required.');
    }
    if (reorderLevel < 0) {
      throw ArgumentError.value(reorderLevel, 'reorderLevel');
    }
    final database = await _database.database;
    if (id == null) {
      await database.insert('inventory_items', {
        'item_id': newRecordId(),
        'item_name': name.trim(),
        'category': category.trim(),
        'unit': unit.trim(),
        'reorder_level': reorderLevel,
        'notes': notes.trim(),
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      return;
    }

    final updated = await database.update(
      'inventory_items',
      {
        'item_name': name.trim(),
        'category': category.trim(),
        'unit': unit.trim(),
        'reorder_level': reorderLevel,
        'notes': notes.trim(),
      },
      where: 'item_id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (updated != 1) throw StateError('The inventory item could not be updated.');
  }

  Future<void> recordMovement({
    required InventoryItem item,
    required String direction,
    required double quantity,
    required double unitCost,
    required String supplier,
    required String reference,
    required String notes,
  }) async {
    if (direction != 'in' && direction != 'out') {
      throw ArgumentError.value(direction, 'direction');
    }
    if (quantity <= 0 || unitCost < 0) {
      throw ArgumentError('Quantity must be positive and cost cannot be negative.');
    }
    final database = await _database.database;
    await database.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT COALESCE(SUM(
          CASE WHEN direction = 'in' THEN quantity ELSE -quantity END
        ), 0) AS balance
        FROM inventory_movements WHERE item_id = ?
        ''',
        [item.id],
      );
      final current = (rows.single['balance']! as num).toDouble();
      if (direction == 'out' && quantity > current) {
        throw StateError(
          'Cannot issue ${quantity.toStringAsFixed(2)} ${item.unit}; '
          'only ${current.toStringAsFixed(2)} ${item.unit} is in stock.',
        );
      }
      await transaction.insert('inventory_movements', {
        'movement_id': newRecordId(),
        'item_id': item.id,
        'direction': direction,
        'quantity': quantity,
        'unit_cost': unitCost,
        'supplier': supplier.trim(),
        'reference': reference.trim(),
        'notes': notes.trim(),
        'moved_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
  }

  Future<List<InventoryMovement>> getMovements(String itemId) async {
    final database = await _database.database;
    final rows = await database.query(
      'inventory_movements',
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'moved_at DESC',
    );
    return rows
        .map(InventoryMovement.fromDatabaseMap)
        .toList(growable: false);
  }

  Future<InventoryImportCounts> importItems(
    List<InventoryImportItem> items,
  ) async {
    final database = await _database.database;
    var imported = 0;
    var updated = 0;
    var unchanged = 0;
    final now = DateTime.now().toIso8601String();

    await database.transaction((transaction) async {
      for (final item in items) {
        if (item.name.trim().isEmpty ||
            item.category.trim().isEmpty ||
            (item.reorderLevel != null && item.reorderLevel! < 0) ||
            (item.openingQuantity != null && item.openingQuantity! < 0) ||
            (item.unitCost != null && item.unitCost! < 0)) {
          throw ArgumentError('An inventory import row contains invalid values.');
        }
        final existing = await transaction.rawQuery(
          '''
          SELECT item_id FROM inventory_items
          WHERE lower(item_name) = lower(?) AND lower(category) = lower(?)
          LIMIT 1
          ''',
          [item.name.trim(), item.category.trim()],
        );
        if (existing.isNotEmpty) {
          final itemId = existing.single['item_id']! as String;
          final savedRows = await transaction.query(
            'inventory_items',
            where: 'item_id = ?',
            whereArgs: [itemId],
            limit: 1,
          );
          final saved = savedRows.single;
          final values = <String, Object?>{
            if (item.unit.trim().isNotEmpty) 'unit': item.unit.trim(),
            if (item.reorderLevel != null)
              'reorder_level': item.reorderLevel,
            'notes': item.notes.trim(),
          }..removeWhere(
            (field, value) =>
                (field == 'notes' && (value as String).isEmpty) ||
                saved[field] == value,
          );
          if (values.isNotEmpty) {
            await transaction.update(
              'inventory_items',
              values,
              where: 'item_id = ?',
              whereArgs: [itemId],
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
            updated++;
          } else {
            unchanged++;
          }
          continue;
        }

        if (item.unit.trim().isEmpty) {
          throw ArgumentError(
            'A new inventory item must include a unit. Add it to the workbook and try again.',
          );
        }
        final itemId = newRecordId();
        await transaction.insert(
          'inventory_items',
          {
            'item_id': itemId,
            'item_name': item.name.trim(),
            'category': item.category.trim(),
            'unit': item.unit.trim(),
            'reorder_level': item.reorderLevel ?? 0,
            'notes': item.notes.trim(),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        final openingQuantity = item.openingQuantity ?? 0;
        if (openingQuantity > 0) {
          await transaction.insert(
            'inventory_movements',
            {
              'movement_id': newRecordId(),
              'item_id': itemId,
              'direction': 'in',
              'quantity': openingQuantity,
              'unit_cost': item.unitCost ?? 0,
              'supplier': item.supplier.trim(),
              'reference': item.reference.trim(),
              'notes': 'Opening stock import',
              'moved_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        imported++;
      }
    });

    return InventoryImportCounts(
      imported: imported,
      updated: updated,
      unchanged: unchanged,
    );
  }
}

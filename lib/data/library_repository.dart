import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';
import 'library_excel_importer.dart';
import 'record_id.dart';

class LibraryBook {
  final String id;
  final String className;
  final String subject;
  final String title;
  final String author;
  final String publisher;

  const LibraryBook({
    required this.id,
    required this.className,
    required this.subject,
    required this.title,
    required this.author,
    required this.publisher,
  });

  factory LibraryBook.fromDatabaseMap(Map<String, Object?> row) => LibraryBook(
    id: row['book_id']! as String,
    className: row['class_name']! as String,
    subject: row['subject']! as String,
    title: row['title']! as String,
    author: (row['author'] as String?) ?? '',
    publisher: (row['publisher'] as String?) ?? '',
  );
}

class LibraryImportCounts {
  final int imported;
  final int updated;
  final int unchanged;

  const LibraryImportCounts({
    required this.imported,
    required this.updated,
    required this.unchanged,
  });
}

class LibraryRepository {
  Future<List<LibraryBook>> getBooks({String search = ''}) async {
    final database = await AppDatabase.instance.database;
    final normalizedSearch = '%${search.trim()}%';
    final rows = await database.query(
      'library_books',
      where: search.trim().isEmpty ? null : 'title LIKE ? OR subject LIKE ? OR class_name LIKE ? OR author LIKE ?',
      whereArgs: search.trim().isEmpty
          ? null
          : List<Object?>.filled(4, normalizedSearch),
      orderBy: 'class_name COLLATE NOCASE, subject COLLATE NOCASE, title COLLATE NOCASE',
    );
    return rows.map(LibraryBook.fromDatabaseMap).toList(growable: false);
  }

  Future<LibraryImportCounts> importBooks(List<LibraryImportBook> books) async {
    final database = await AppDatabase.instance.database;
    var imported = 0;
    var updated = 0;
    var unchanged = 0;
    await database.transaction((transaction) async {
      for (final book in books) {
        final existing = await transaction.query(
          'library_books',
          where: 'import_key = ? OR (LOWER(TRIM(class_name)) = LOWER(TRIM(?)) AND LOWER(TRIM(subject)) = LOWER(TRIM(?)) AND LOWER(TRIM(title)) = LOWER(TRIM(?)))',
          whereArgs: [book.importKey, book.className, book.subject, book.title],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final row = existing.single;
          final values =
              <String, Object?>{
                'class_name': book.className,
                'subject': book.subject,
                'title': book.title,
                'author': book.author,
                'publisher': book.publisher,
              }..removeWhere(
                (field, value) =>
                    (field == 'author' || field == 'publisher') &&
                        (value as String).trim().isEmpty ||
                    row[field] == value,
              );
          if (values.isNotEmpty) {
            await transaction.update(
              'library_books',
              values,
              where: 'book_id = ?',
              whereArgs: [row['book_id']],
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
            updated++;
          } else {
            unchanged++;
          }
          continue;
        }
        await transaction.insert('library_books', {
          'book_id': newRecordId(),
          'class_name': book.className,
          'subject': book.subject,
          'title': book.title,
          'author': book.author,
          'publisher': book.publisher,
          'import_key': book.importKey,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        imported++;
      }
    });
    return LibraryImportCounts(
      imported: imported,
      updated: updated,
      unchanged: unchanged,
    );
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';

import 'excel_workbook_decoder.dart';

class LibraryImportBook {
  final String importKey;
  final String className;
  final String subject;
  final String title;
  final String author;
  final String publisher;

  const LibraryImportBook({
    required this.importKey,
    required this.className,
    required this.subject,
    required this.title,
    required this.author,
    required this.publisher,
  });
}

class LibraryExcelImportResult {
  final List<LibraryImportBook> books;
  final int skippedBlankRows;
  final List<String> errors;

  const LibraryExcelImportResult({
    required this.books,
    required this.skippedBlankRows,
    required this.errors,
  });
}

class LibraryExcelImporter {
  LibraryExcelImportResult parse(List<int> bytes) {
    final workbook = ExcelWorkbookDecoder.decode(bytes);
    for (final sheet in workbook.tables.values) {
      final rows = sheet.rows;
      final blocks = <_BookBlock>[];
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        for (final start in [1, 6]) {
          if (_isBookHeader(rows[rowIndex], start)) {
            blocks.add(
              _BookBlock(start, rowIndex, _classBefore(rows, start, rowIndex)),
            );
          }
        }
      }
      if (blocks.isEmpty) continue;
      blocks.sort((left, right) {
        final byRow = left.headerIndex.compareTo(right.headerIndex);
        return byRow == 0 ? left.start.compareTo(right.start) : byRow;
      });

      final books = <LibraryImportBook>[];
      final errors = <String>[];
      final seen = <String>{};
      var skippedBlankRows = 0;
      for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
        final block = blocks[blockIndex];
        var className = block.className;
        var currentSubject = '';
        final nextHeaderIndex = blocks
            .skip(blockIndex + 1)
            .where((next) => next.start == block.start)
            .map((next) => next.headerIndex)
            .firstOrNull;
        for (
          var rowIndex = block.headerIndex + 1;
          rowIndex < (nextHeaderIndex ?? rows.length);
          rowIndex++
        ) {
          final row = rows[rowIndex];
          var subject = _value(row, block.start);
          final title = _value(row, block.start + 1);
          final author = _value(row, block.start + 2);
          final publisher = _value(row, block.start + 3);
          if ([
            subject,
            title,
            author,
            publisher,
          ].every((value) => value.isEmpty)) {
            skippedBlankRows++;
            continue;
          }
          if (title.isEmpty) {
            skippedBlankRows++;
            continue;
          }
          if (subject.isNotEmpty) currentSubject = subject;
          subject = currentSubject;
          if (subject.isEmpty || className.isEmpty) {
            errors.add(
              'Row ${rowIndex + 1} is missing a class or subject for "$title".',
            );
            continue;
          }
          final keyParts = [className, subject, title]
              .map(_normalize)
              .toList(growable: false);
          final normalizedKey = keyParts.join('\u001f');
          if (!seen.add(normalizedKey)) {
            skippedBlankRows++;
            continue;
          }
          final importKey =
              'book:${sha256.convert(utf8.encode(normalizedKey)).toString()}';
          books.add(
            LibraryImportBook(
              importKey: importKey,
              className: className,
              subject: subject,
              title: title,
              author: author,
              publisher: publisher,
            ),
          );
        }
      }
      return LibraryExcelImportResult(
        books: books,
        skippedBlankRows: skippedBlankRows,
        errors: errors,
      );
    }
    throw const FormatException(
      'No worksheet contains Subject, Books / Printed Copies, Author, and Publisher columns.',
    );
  }

  bool _isBookHeader(List<Data?> row, int start) {
    final cells = List.generate(
      4,
      (index) => _normalize(_value(row, start + index)),
    );
    final hasBookHeaders =
        cells[1] == 'booksprintedcopies' ||
        cells[1] == 'booksprintedcopy' ||
        cells[1] == 'textbook' ||
        cells[1] == 'textbooks';
    return (cells[0] == 'subject' || cells[0] == 'subjects') &&
        hasBookHeaders;
  }

  String _classBefore(List<List<Data?>> rows, int start, int headerIndex) {
    for (var index = headerIndex - 1; index >= 0; index--) {
      final value = _value(rows[index], start);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _value(List<Data?> row, int column) =>
      column >= row.length ? '' : _cellText(row[column]).trim();

  String _cellText(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text?.trim() ?? '';
    return value.toString().trim();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

class _BookBlock {
  final int start;
  final int headerIndex;
  final String className;

  const _BookBlock(this.start, this.headerIndex, this.className);
}

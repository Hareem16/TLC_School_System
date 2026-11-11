import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_excel_importer.dart';
import '../data/library_repository.dart';

class LibraryPage extends StatefulWidget {
  final Color primaryColor;
  final bool canManageRecords;

  const LibraryPage({
    super.key,
    required this.primaryColor,
    this.canManageRecords = false,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final LibraryRepository _repository = LibraryRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<LibraryBook>> _books;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _books = _repository.getBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _books = _repository.getBooks(search: _searchController.text);
  }

  Future<void> _importExcel() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select book-list workbook',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (files.isEmpty) return;
      final result = LibraryExcelImporter().parse(
        await files.first.readAsBytes(),
      );
      if (result.errors.isNotEmpty) {
        if (!mounted) return;
        await _showErrors(result.errors);
        return;
      }
      if (result.books.isEmpty) {
        throw const FormatException('No book records were found to import.');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import library book list?'),
          content: Text(
            '${result.books.length} class book-list entries are ready. Matching records will be updated when workbook values differ; blank author or publisher cells preserve saved values.'
            '${result.skippedBlankRows == 0 ? '' : '\n${result.skippedBlankRows} blank or repeated rows will be ignored.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import Books'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final counts = await _repository.importBooks(result.books);
      if (!mounted) return;
      setState(_reload);
      _message(
        'Import complete: ${counts.imported} added, '
        '${counts.updated} updated, ${counts.unchanged} unchanged.',
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Book list import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showErrors(List<String> errors) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Workbook needs review'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('No book records were imported. Review these rows:'),
            const SizedBox(height: 12),
            for (final error in errors) Text(error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LibraryBook>>(
    future: _books,
    builder: (context, snapshot) {
      final books = snapshot.data ?? const <LibraryBook>[];
      final classes = books.map((book) => book.className).toSet().length;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'LIBRARY & BOOK LISTS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Class-wise curriculum book register imported from the supplied workbook.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF727B89),
                  ),
                ),
                if (widget.canManageRecords) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                        onPressed: _importing ? null : _importExcel,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _importing ? 'Importing...' : 'Import Excel',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                        ),
                      ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _LibraryNotice(message: _error!),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryBox(
                        title: 'Book-list entries',
                        value: '${books.length}',
                        icon: Icons.menu_book_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryBox(
                        title: 'Classes represented',
                        value: '$classes',
                        icon: Icons.meeting_room_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(_reload),
                  decoration: InputDecoration(
                    hintText: 'Search title, subject, class, or author',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  _LibraryNotice(
                    message:
                        'Book records could not be loaded: ${snapshot.error}',
                  )
                else if (books.isEmpty)
                  const _EmptyLibrary()
                else
                  Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE7E9EE)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        border: TableBorder.all(
                          color: const Color(0xFFD7DCE3),
                          width: 0.7,
                        ),
                        headingTextStyle: const TextStyle(
                          color: Color(0xFF687080),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                        columns: const [
                          DataColumn(label: Center(child: Text('CLASS'))),
                          DataColumn(label: Center(child: Text('SUBJECT'))),
                          DataColumn(
                            label: Center(child: Text('BOOK / PRINTED COPY')),
                          ),
                          DataColumn(label: Center(child: Text('AUTHOR'))),
                          DataColumn(label: Center(child: Text('PUBLISHER'))),
                        ],
                        rows: [
                          for (final book in books)
                            DataRow(
                              cells: [
                                DataCell(Text(book.className)),
                                DataCell(Text(book.subject)),
                                DataCell(
                                  SizedBox(
                                    width: 300,
                                    child: Text(
                                      book.title,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(book.author)),
                                DataCell(Text(book.publisher)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'This workbook is a curriculum book list, not an inventory stock count. Copies held or issued are not inferred.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF727B89)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SummaryBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryBox({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFC62828), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11, color: Color(0xFF687080)),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF252B36),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LibraryNotice extends StatelessWidget {
  final String message;

  const _LibraryNotice({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F0),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF1CBCB)),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFF9A2222))),
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(30),
    child: Column(
      children: [
        Icon(Icons.menu_book_outlined, size: 34, color: Color(0xFFC62828)),
        SizedBox(height: 10),
        Text(
          'No book lists imported yet.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          'Import BOOKS LISTS SESSION 2026-2027.xlsx to populate this class-wise library register.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF727B89), fontSize: 12),
        ),
      ],
    ),
  );
}

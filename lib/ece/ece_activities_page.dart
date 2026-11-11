import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/app_database.dart';
import '../data/record_id.dart';

class EceActivitiesPage extends StatefulWidget {
  const EceActivitiesPage({super.key});

  @override
  State<EceActivitiesPage> createState() => _EceActivitiesPageState();
}

class _EceActivitiesPageState extends State<EceActivitiesPage> {
  List<Map<String, Object?>> _worksheets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('ece_worksheets', orderBy: 'created_at DESC');
    if (mounted) {
      setState(() {
        _worksheets = rows;
        _loading = false;
      });
    }
  }

  Future<void> _importWorksheet() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final db = await AppDatabase.instance.database;
    await db.insert('ece_worksheets', {
      'worksheet_id': newRecordId(),
      'title': file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      'class_name': 'ECE',
      'subject': 'General',
      'instructions': '',
      'activity_text': '',
      'file_name': file.name,
      'file_bytes': bytes,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _load();
    if (mounted) _toast('Worksheet imported.');
  }

  Future<void> _createWorksheet() async {
    final title = TextEditingController();
    final className = TextEditingController(text: 'ECE');
    final subject = TextEditingController();
    final instructions = TextEditingController();
    final activity = TextEditingController();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create ECE worksheet'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Worksheet title',
                    ),
                    validator: _required,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: className,
                          decoration: const InputDecoration(labelText: 'Class'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: subject,
                          decoration: const InputDecoration(
                            labelText: 'Subject / area',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instructions,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Instructions',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: activity,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Activity prompt or content',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save worksheet'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final db = await AppDatabase.instance.database;
      await db.insert('ece_worksheets', {
        'worksheet_id': newRecordId(),
        'title': title.text.trim(),
        'class_name': className.text.trim(),
        'subject': subject.text.trim(),
        'instructions': instructions.text.trim(),
        'activity_text': activity.text.trim(),
        'file_name': '',
        'file_bytes': null,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _load();
    }
    title.dispose();
    className.dispose();
    subject.dispose();
    instructions.dispose();
    activity.dispose();
  }

  Future<List<Uint8List>> _worksheetImages(
    Map<String, Object?> worksheet,
  ) async {
    final data = worksheet['file_bytes'] as Uint8List?;
    final fileName = (worksheet['file_name'] as String?) ?? '';
    if (data != null && fileName.toLowerCase().endsWith('.pdf')) {
      final pages = <Uint8List>[];
      await for (final page in Printing.raster(data, dpi: 120)) {
        pages.add(await page.toPng());
      }
      return pages;
    }
    if (data != null) return [data];
    final source = pw.Document();
    source.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '${worksheet['title']}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Class: ${worksheet['class_name']}     Subject: ${worksheet['subject']}',
            ),
            pw.SizedBox(height: 18),
            if ((worksheet['instructions'] as String).isNotEmpty)
              pw.Text(
                '${worksheet['instructions']}',
                style: const pw.TextStyle(fontSize: 12),
              ),
            if ((worksheet['activity_text'] as String).isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(
                '${worksheet['activity_text']}',
                style: const pw.TextStyle(fontSize: 15, lineSpacing: 5),
              ),
            ],
            pw.Spacer(),
            for (var i = 0; i < 6; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 16),
                child: pw.Divider(),
              ),
          ],
        ),
      ),
    );
    final sourceBytes = await source.save();
    final page = await Printing.raster(
      sourceBytes,
      pages: const [0],
      dpi: 120,
    ).first;
    return [await page.toPng()];
  }

  Future<void> _printTwice(Map<String, Object?> worksheet) async {
    try {
      final images = await _worksheetImages(worksheet);
      final output = pw.Document();
      for (final imageBytes in images) {
        final source = pw.MemoryImage(imageBytes);
        output.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(18),
            build: (_) => pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _copyPanel('C.W.', source),
                pw.SizedBox(width: 14),
                _copyPanel('H.W.', source),
              ],
            ),
          ),
        );
      }
      await Printing.layoutPdf(
        onLayout: (_) async => output.save(),
        name: 'TLC-ECE-${worksheet['title']}-CW-HW.pdf',
      );
    } catch (error) {
      _toast('Worksheet could not be printed: $error');
    }
  }

  pw.Widget _copyPanel(String label, pw.MemoryImage image) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(5),
          color: PdfColor.fromInt(0xFFC62828),
          child: pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700),
            ),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      ],
    ),
  );

  Future<void> _delete(Map<String, Object?> worksheet) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete worksheet?'),
        content: Text('Delete “${worksheet['title']}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final db = await AppDatabase.instance.database;
      await db.delete(
        'ece_worksheets',
        where: 'worksheet_id = ?',
        whereArgs: [worksheet['worksheet_id']],
      );
      await _load();
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(
      title: const Text('ECE Activities & Worksheets'),
      actions: [
        IconButton(
          tooltip: 'Import PDF or image',
          onPressed: _importWorksheet,
          icon: const Icon(Icons.file_upload_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createWorksheet,
      icon: const Icon(Icons.add),
      label: const Text('Create Worksheet'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _worksheets.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.draw_outlined,
                    size: 46,
                    color: Color(0xFFC62828),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Import a worksheet PDF or image, or create one here.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _importWorksheet,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import worksheet'),
                  ),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              for (final worksheet in _worksheets)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.draw_outlined),
                    ),
                    title: Text('${worksheet['title']}'),
                    subtitle: Text(
                      '${worksheet['class_name']} · ${worksheet['subject']}  ${worksheet['file_name'] == '' ? '• Created in app' : '• ${worksheet['file_name']}'}',
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Print C.W. and H.W. copies',
                          onPressed: () => _printTwice(worksheet),
                          icon: const Icon(Icons.print_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete worksheet',
                          onPressed: () => _delete(worksheet),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}

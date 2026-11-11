import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../auth/app_user.dart';
import '../data/app_database.dart';
import '../data/record_id.dart';
import '../school_profile.dart';

class NoticesPage extends StatefulWidget {
  final AppUser user;
  final SchoolProfile profile;

  const NoticesPage({super.key, required this.user, required this.profile});

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  List<Map<String, Object?>> _notices = [];
  bool _loading = true;
  bool get _canPublish => AppRoles.fullAccessRoles.contains(widget.user.role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('school_notices', orderBy: 'created_at DESC');
      final visible = AppRoles.fullAccessRoles.contains(widget.user.role)
          ? rows
          : rows.where((notice) {
              final audience = notice['audience'];
              if (widget.user.role == AppRoles.parent ||
                  widget.user.role == AppRoles.student) {
                return audience == 'All school' ||
                    audience == 'Parents / guardians';
              }
              if (widget.user.role == AppRoles.teacher) {
                return audience == 'All school' || audience == 'Staff';
              }
              return audience == 'All school';
            }).toList();
      if (mounted) {
        setState(() {
          _notices = visible;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _toast('Notices could not be loaded: $error');
        });
      }
    }
  }

  Future<void> _create() async {
    if (!_canPublish) return;
    final title = TextEditingController();
    final body = TextEditingController();
    var audience = 'All school';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Create official notice'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Notice title',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: audience,
                    decoration: const InputDecoration(labelText: 'Audience'),
                    items: const [
                      DropdownMenuItem(
                        value: 'All school',
                        child: Text('All school'),
                      ),
                      DropdownMenuItem(
                        value: 'Parents / guardians',
                        child: Text('Parents / guardians'),
                      ),
                      DropdownMenuItem(value: 'Staff', child: Text('Staff')),
                    ],
                    onChanged: (value) {
                      if (value != null) update(() => audience = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: body,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Notice text',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
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
                if (title.text.trim().isNotEmpty &&
                    body.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save notice'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final db = await AppDatabase.instance.database;
      await db.insert('school_notices', {
        'notice_id': newRecordId(),
        'title': title.text.trim(),
        'audience': audience,
        'body': body.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await _load();
    }
    title.dispose();
    body.dispose();
  }

  Future<Uint8List> _makePdf(Map<String, Object?> notice) async {
    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    final accent = PdfColor.fromInt(widget.profile.primaryColor.toARGB32());
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                pw.Image(pw.MemoryImage(logoBytes), width: 58, height: 58),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        widget.profile.schoolName,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (widget.profile.address.trim().isNotEmpty)
                        pw.Text(
                          widget.profile.address,
                          textAlign: pw.TextAlign.center,
                        ),
                      if (widget.profile.phone.trim().isNotEmpty)
                        pw.Text(
                          widget.profile.phone,
                          textAlign: pw.TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(height: 2, color: accent),
            pw.SizedBox(height: 18),
            pw.Text(
              'OFFICIAL SCHOOL NOTICE',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                children: [
                  pw.SizedBox(width: 180, child: pw.Divider()),
                  pw.Text(
                    'Principal / Authorized Head',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '${notice['title']}',
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                'Date: ${(notice['created_at'] as String).split('T').first}',
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'For: ${notice['audience']}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            '${notice['body']}',
            style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> _print(Map<String, Object?> notice) async {
    try {
      final bytes = await _makePdf(notice);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'TLC-notice.pdf',
      );
    } catch (error) {
      _toast('Notice PDF could not be prepared: $error');
    }
  }

  Future<void> _savePdf(Map<String, Object?> notice) async {
    try {
      final bytes = await _makePdf(notice);
      await FilePicker.saveFile(
        fileName: 'TLC-notice-${_safeFileName(notice['title'])}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    } catch (error) {
      _toast('Notice PDF could not be saved: $error');
    }
  }

  Future<void> _share(Map<String, Object?> notice) async {
    try {
      final bytes = await _makePdf(notice);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'TLC-notice-${_safeFileName(notice['title'])}.pdf',
      );
    } catch (error) {
      _toast('Notice PDF could not be shared: $error');
    }
  }

  String _safeFileName(Object? title) => '${title ?? 'notice'}'
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');

  Future<void> _delete(Map<String, Object?> notice) async {
    if (!_canPublish) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notice?'),
        content: Text('Delete “${notice['title']}”?'),
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
        'school_notices',
        where: 'notice_id = ?',
        whereArgs: [notice['notice_id']],
      );
      await _load();
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(
      title: const Text('Official Notices'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: _canPublish
        ? FloatingActionButton.extended(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('New Notice'),
          )
        : null,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _notices.isEmpty
        ? const Center(
            child: Text('No official notices have been saved on this device.'),
          )
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              for (final notice in _notices)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.campaign_outlined),
                    ),
                    title: Text('${notice['title']}'),
                    subtitle: Text(
                      '${notice['audience']}  •  ${(notice['created_at'] as String).split('T').first}\n${notice['body']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Print / share PDF',
                          onPressed: () => _print(notice),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                        ),
                        IconButton(
                          tooltip: 'Save PDF',
                          onPressed: () => _savePdf(notice),
                          icon: const Icon(Icons.download_outlined),
                        ),
                        IconButton(
                          tooltip: 'Share PDF',
                          onPressed: () => _share(notice),
                          icon: const Icon(Icons.share_outlined),
                        ),
                        if (_canPublish)
                          IconButton(
                            tooltip: 'Delete notice',
                            onPressed: () => _delete(notice),
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

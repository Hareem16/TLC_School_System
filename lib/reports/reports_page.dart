import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../auth/app_user.dart';
import '../data/app_database.dart';
import '../school_profile.dart';

class ReportsPage extends StatefulWidget {
  final AppUser user;
  final SchoolProfile profile;

  const ReportsPage({super.key, required this.user, required this.profile});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  static const _baseReports = [
    'Students',
    'Attendance',
    'Fees',
    'Exams & Tabulation',
    'Payroll',
    'Inventory',
  ];
  String _report = '';
  String _className = 'All classes';
  final _month = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 7),
  );
  List<String> _classes = ['All classes'];
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;
  bool _working = false;

  bool get _admin => AppRoles.fullAccessRoles.contains(widget.user.role);
  bool _canRunReport(String report) => switch (report) {
    'Students' => _admin || widget.user.canAccess('Students'),
    'Attendance' => _admin || widget.user.canAccess('Attendance'),
    'Fees' => _admin || widget.user.canAccess('Fees & Vouchers'),
    'Exams & Tabulation' =>
      _admin ||
          widget.user.canAccess('Examinations') ||
          widget.user.canAccess('Results & Report Cards'),
    'Payroll' => _admin,
    'Inventory' => _admin || widget.user.canAccess('Inventory'),
    'Complaints' => _admin,
    _ => false,
  };
  List<String> get _reports => [
    for (final report in _baseReports)
      if (_canRunReport(report)) report,
    if (_admin) 'Complaints',
  ];

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  @override
  void dispose() {
    _month.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT class_name FROM students WHERE TRIM(class_name) <> '' ORDER BY class_name",
    );
    _classes = [
      'All classes',
      ...rows.map((row) => row['class_name'] as String),
    ];
    if (!_reports.contains(_report) && _reports.isNotEmpty) {
      _report = _reports.first;
    }
    await _loadReport();
  }

  Future<List<Map<String, Object?>>> _queryReport() async {
    if (!_canRunReport(_report)) {
      throw StateError('Your account cannot run the $_report report.');
    }
    final db = await AppDatabase.instance.database;
    final classWhere = _className == 'All classes'
        ? ''
        : ' AND s.class_name = ?';
    final month = _month.text.trim();
    final monthLike = month.length == 7 ? '$month%' : '%';
    final classArgs = _className == 'All classes'
        ? <Object?>[]
        : <Object?>[_className];
    switch (_report) {
      case 'Students':
        return db.rawQuery(
          'SELECT admission_number AS gr_number, first_name || " " || last_name AS student, class_name, COALESCE(section_name, "") AS section, guardian_name, guardian_phone, monthly_fee FROM students WHERE date_of_removal IS NULL${_className == 'All classes' ? '' : ' AND class_name = ?'} ORDER BY class_name, first_name',
          classArgs,
        );
      case 'Attendance':
        return db.rawQuery(
          'SELECT a.attendance_date, s.class_name, s.admission_number AS gr_number, s.first_name || " " || s.last_name AS student, a.status, COALESCE(a.notes, "") AS notes FROM attendance a JOIN students s ON s.student_id = a.student_id WHERE a.attendance_date LIKE ?$classWhere ORDER BY a.attendance_date DESC, s.class_name, student',
          [monthLike, ...classArgs],
        );
      case 'Fees':
        return db.rawQuery(
          'SELECT c.month_key, s.class_name, s.admission_number AS gr_number, s.first_name || " " || s.last_name AS student, c.amount_due, COALESCE((SELECT SUM(p.amount) FROM fee_payments p WHERE p.fee_id = c.fee_id), 0) - COALESCE((SELECT SUM(r.amount) FROM fee_payment_reversals r JOIN fee_payments p ON p.payment_id = r.payment_id WHERE p.fee_id = c.fee_id), 0) AS amount_paid, c.amount_due - COALESCE((SELECT SUM(p.amount) FROM fee_payments p WHERE p.fee_id = c.fee_id), 0) + COALESCE((SELECT SUM(r.amount) FROM fee_payment_reversals r JOIN fee_payments p ON p.payment_id = r.payment_id WHERE p.fee_id = c.fee_id), 0) AS balance FROM fee_charges c JOIN students s ON s.student_id = c.student_id WHERE c.month_key LIKE ?$classWhere ORDER BY c.month_key DESC, s.class_name, student',
          [monthLike, ...classArgs],
        );
      case 'Exams & Tabulation':
        return db.rawQuery(
          'SELECT e.exam_name, e.class_name, s.subject_name, st.admission_number AS gr_number, st.first_name || " " || st.last_name AS student, r.marks_obtained, s.total_marks, ROUND(r.marks_obtained * 100.0 / s.total_marks, 2) AS percentage FROM exam_results r JOIN exam_subjects s ON s.subject_id = r.subject_id JOIN exams e ON e.exam_id = s.exam_id JOIN students st ON st.student_id = r.student_id WHERE 1=1${_className == 'All classes' ? '' : ' AND e.class_name = ?'} ORDER BY e.exam_name, e.class_name, student, s.subject_name',
          classArgs,
        );
      case 'Payroll':
        return db.rawQuery(
          "SELECT employee_number, full_name AS teacher, role AS designation, monthly_salary AS base_salary, ? AS month, monthly_salary AS net_salary FROM staff WHERE LOWER(role) LIKE '%teacher%' ORDER BY full_name COLLATE NOCASE",
          [month],
        );
      case 'Inventory':
        return db.rawQuery(
          'SELECT i.item_name, i.category, i.unit, COALESCE(SUM(CASE WHEN m.direction = "in" THEN m.quantity ELSE -m.quantity END), 0) AS quantity, i.reorder_level, i.notes FROM inventory_items i LEFT JOIN inventory_movements m ON m.item_id = i.item_id GROUP BY i.item_id ORDER BY i.category, i.item_name',
        );
      case 'Complaints':
        if (!_admin) {
          throw StateError(
            'Only administrators and the principal may run complaint reports.',
          );
        }
        return db.rawQuery(
          'SELECT created_at, reporter_name, category, subject, priority, status, resolution_notes FROM complaints ORDER BY created_at DESC',
        );
      default:
        return [];
    }
  }

  Future<void> _loadReport() async {
    if (_report.isEmpty) {
      if (mounted) {
        setState(() {
          _rows = [];
          _loading = false;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await _queryReport();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _rows = [];
          _loading = false;
        });
        _toast('Report could not be loaded: $error');
      }
    }
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) {
      _toast('There are no rows to export.');
      return;
    }
    setState(() => _working = true);
    try {
      final workbook = Excel.createExcel();
      final sheet = workbook['Report'];
      final columns = _rows.first.keys.toList();
      sheet.appendRow(
        columns.map((key) => TextCellValue(_label(key))).toList(),
      );
      for (final row in _rows) {
        sheet.appendRow(
          columns.map((key) => TextCellValue('${row[key] ?? ''}')).toList(),
        );
      }
      final bytes = workbook.encode();
      if (bytes == null) throw StateError('Workbook encoding failed.');
      await FilePicker.saveFile(
        fileName:
            'TLC-${_slug(_report)}-${DateTime.now().toIso8601String().substring(0, 10)}.xlsx',
        bytes: Uint8List.fromList(bytes),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } catch (error) {
      _toast('Spreadsheet could not be saved: $error');
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _printPdf() async {
    if (_rows.isEmpty) {
      _toast('There are no rows to print.');
      return;
    }
    setState(() => _working = true);
    try {
      final doc = pw.Document();
      final columns = _rows.first.keys.toList();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(22),
          build: (_) => [
            pw.Text(
              widget.profile.schoolName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15),
            ),
            pw.Text(
              '$_report Report${_className == 'All classes' ? '' : ' · Class $_className'}${_month.text.trim().isEmpty ? '' : ' · ${_month.text.trim()}'}',
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    for (final key in columns)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          _label(key),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final row in _rows)
                  pw.TableRow(
                    children: [
                      for (final key in columns)
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            '${row[key] ?? ''}',
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'TLC-${_slug(_report)}.pdf',
      );
    } catch (error) {
      _toast('PDF could not be prepared: $error');
    }
    if (mounted) setState(() => _working = false);
  }

  String _label(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
  String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(
      title: const Text('School Reports'),
      actions: [
        IconButton(onPressed: _loadReport, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: _reports.isEmpty
        ? const Center(child: Text('No reports are enabled for this account.'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 230,
                      child: DropdownButtonFormField<String>(
                        initialValue: _report,
                        decoration: const InputDecoration(
                          labelText: 'Report',
                          border: OutlineInputBorder(),
                        ),
                        items: _reports
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _report = value);
                          _loadReport();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _classes.contains(_className)
                            ? _className
                            : 'All classes',
                        decoration: const InputDecoration(
                          labelText: 'Class filter',
                          border: OutlineInputBorder(),
                        ),
                        items: _classes
                            .map(
                              (name) => DropdownMenuItem(
                                value: name,
                                child: Text(name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _className = value);
                          _loadReport();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _month,
                        decoration: const InputDecoration(
                          labelText: 'Month YYYY-MM',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _loadReport(),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _working ? null : _exportExcel,
                      icon: const Icon(Icons.table_view_outlined),
                      label: const Text('Excel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _working ? null : _printPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF / Print'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
                    ? const Center(
                        child: Text('No records match these filters.'),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: _rows.first.keys
                                .map(
                                  (key) => DataColumn(label: Text(_label(key))),
                                )
                                .toList(),
                            rows: _rows
                                .take(300)
                                .map(
                                  (row) => DataRow(
                                    cells: row.values
                                        .map(
                                          (value) =>
                                              DataCell(Text('${value ?? ''}')),
                                        )
                                        .toList(),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
              ),
            ],
          ),
  );
}

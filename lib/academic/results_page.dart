import 'dart:async';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../auth/app_user.dart';
import '../data/app_database.dart';
import '../school_profile.dart';

class ResultsPage extends StatefulWidget {
  final AppUser user;
  final SchoolProfile profile;

  const ResultsPage({super.key, required this.user, required this.profile});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  List<Map<String, Object?>> _exams = [];
  List<Map<String, Object?>> _students = [];
  List<Map<String, Object?>> _subjects = [];
  Map<String, Map<String, Object?>> _marks = {};
  String? _examId;
  String? _studentId;
  bool _loading = true;
  bool _working = false;
  bool _refreshInProgress = false;
  Timer? _refreshTimer;
  String? _error;

  bool get _isManager => AppRoles.fullAccessRoles.contains(widget.user.role);
  Set<String> get _classScope => widget.user.assignedClassSections.toSet();
  bool _examInScope(Map<String, Object?> exam) => _classScope.contains(
    '${(exam['class_name'] as String).trim()}\u001f'
    '${((exam['section_name'] as String?) ?? '').trim()}',
  );

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_working) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    try {
      final db = await AppDatabase.instance.database;
      final all = await db.query('exams', orderBy: 'start_date DESC');
      _exams = _isManager ? all : all.where(_examInScope).toList();
      if (_examId == null ||
          !_exams.any((item) => item['exam_id'] == _examId)) {
        _examId = _exams.isEmpty ? null : _exams.first['exam_id'] as String;
      }
      _students = [];
      _subjects = [];
      _marks = {};
      if (_examId != null) {
        final exam = _exams.firstWhere((item) => item['exam_id'] == _examId);
        _subjects = await db.query(
          'exam_subjects',
          where: 'exam_id = ?',
          whereArgs: [_examId],
          orderBy: 'subject_name COLLATE NOCASE',
        );
        _students = await db.query(
          'students',
          where: "TRIM(class_name) = TRIM(?) AND TRIM(COALESCE(section_name, '')) = TRIM(?) AND (date_of_removal IS NULL OR TRIM(date_of_removal) = '')",
          whereArgs: [exam['class_name'], exam['section_name'] ?? ''],
          orderBy: 'first_name COLLATE NOCASE, last_name COLLATE NOCASE',
        );
        if (_studentId == null ||
            !_students.any((row) => row['student_id'] == _studentId)) {
          _studentId = _students.isEmpty
              ? null
              : _students.first['student_id'] as String;
        }
        for (final subject in _subjects) {
          final rows = await db.query(
            'exam_results',
            where: 'subject_id = ?',
            whereArgs: [subject['subject_id']],
          );
          for (final row in rows) {
            _marks['${subject['subject_id']}:${row['student_id']}'] = row;
          }
        }
      }
      if (mounted) {
        setState(() {
          _error = null;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  double _obtained(String studentId, String subjectId) =>
      (_marks['$subjectId:$studentId']?['marks_obtained'] as num?)
          ?.toDouble() ??
      0;

  bool _complete(String studentId) =>
      _subjects.isNotEmpty &&
      _subjects.every(
        (subject) => _marks.containsKey('${subject['subject_id']}:$studentId'),
      );

  double _total(String studentId) => _subjects.fold<double>(
    0,
    (sum, subject) =>
        sum + _obtained(studentId, subject['subject_id'] as String),
  );
  double _maxTotal() => _subjects.fold<double>(
    0,
    (sum, subject) => sum + (subject['total_marks'] as num).toDouble(),
  );
  double _percent(String studentId) =>
      _maxTotal() == 0 ? 0 : _total(studentId) / _maxTotal() * 100;
  String _remark(double percent) => percent >= 80
      ? 'Outstanding'
      : percent >= 70
      ? 'Excellent'
      : percent >= 60
      ? 'Good'
      : percent >= 50
      ? 'Satisfactory'
      : 'Do not meet the expectation';
  String _grade(double percent) => percent >= 80
      ? 'A+'
      : percent >= 70
      ? 'A'
      : percent >= 60
      ? 'B'
      : percent >= 50
      ? 'C'
      : percent >= 40
      ? 'D'
      : 'F';
  String _num(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  List<Map<String, Object?>> _rankedStudents() {
    final rows =
        _students
            .where((row) => _complete(row['student_id'] as String))
            .toList()
          ..sort(
            (a, b) =>
                _percent(b['student_id'] as String)
                    .compareTo(_percent(a['student_id'] as String)),
          );
    var rank = 0;
    double? lastPercent;
    for (var index = 0; index < rows.length; index++) {
      final value = _percent(rows[index]['student_id'] as String);
      if (lastPercent == null || value < lastPercent) rank = index + 1;
      rows[index] = {...rows[index], '_rank': rank};
      lastPercent = value;
    }
    return rows;
  }

  int _rank(String id) =>
      _rankedStudents().firstWhere(
            (row) => row['student_id'] == id,
            orElse: () => const {},
          )['_rank']
          as int? ??
      0;

  Future<void> _printCard() async {
    if (_studentId == null || !_complete(_studentId!)) {
      _toast(
        'Complete marks for this student before generating the report card.',
      );
      return;
    }
    setState(() => _working = true);
    try {
      final student = _students.firstWhere(
        (row) => row['student_id'] == _studentId,
      );
      final exam = _exams.firstWhere((row) => row['exam_id'] == _examId);
      final bytes = await _reportCardsPdf([student], exam);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'TLC-report-card-${student['admission_number']}.pdf',
      );
    } catch (error) {
      _toast('Report card could not be prepared: $error');
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _printAllCards() async {
    final completeStudents = _students
        .where((student) => _complete(student['student_id'] as String))
        .toList(growable: false);
    final incompleteCount = _students.length - completeStudents.length;
    if (completeStudents.isEmpty) {
      _toast('Enter all subject marks before printing class report cards.');
      return;
    }
    if (incompleteCount > 0) {
      final shouldPrint = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some marks are incomplete'),
          content: Text(
            '$incompleteCount student(s) do not have marks for every subject. '
            'Print report cards for the ${completeStudents.length} students '
            'whose marks are complete?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Print complete cards'),
            ),
          ],
        ),
      );
      if (shouldPrint != true || !mounted) return;
    }

    setState(() => _working = true);
    try {
      final exam = _exams.firstWhere((row) => row['exam_id'] == _examId);
      final bytes = await _reportCardsPdf(completeStudents, exam);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'TLC-report-cards-${exam['class_name']}.pdf',
      );
    } catch (error) {
      _toast('Class report cards could not be prepared: $error');
    }
    if (mounted) setState(() => _working = false);
  }

  Future<Uint8List> _reportCardsPdf(
    List<Map<String, Object?>> students,
    Map<String, Object?> exam,
  ) async {
    final doc = pw.Document();
    final attendanceByStudent = await _attendanceSummaries(students);
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/tlc_logo.png')).buffer
          .asUint8List(),
    );
    final schoolNameFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/dancecrazebv.ttf'),
    );
    final accent = PdfColor.fromInt(widget.profile.primaryColor.toARGB32());
    for (final student in students) {
      final id = student['student_id'] as String;
      final max = _maxTotal();
      final percent = _percent(id);
      final rank = _rank(id);
      final graphColors = _subjectGraphColors(id);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: 1.4),
            ),
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.only(bottom: 9),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: accent, width: 1.2),
                    ),
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Image(logo, width: 48, height: 48),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              widget.profile.schoolName,
                              style: pw.TextStyle(
                                font: schoolNameFont,
                                color: accent,
                                fontSize: 22,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'STUDENT ACADEMIC MARKSHEET',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1.1,
                                color: PdfColors.grey800,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              '${exam['exam_name']}  •  ${exam['academic_year']}',
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 5,
                        ),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: accent, width: 0.7),
                        ),
                        child: pw.Text(
                          'OFFICIAL\nRECORD',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            color: accent,
                            fontSize: 6,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table(
                  border: pw.TableBorder.all(width: 0.6),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.1),
                    1: pw.FlexColumnWidth(1.7),
                    2: pw.FlexColumnWidth(1.1),
                    3: pw.FlexColumnWidth(1.7),
                  },
                  children: [
                    _infoRow(
                      'Roll No.',
                      (student['roll_number'] as String?)?.trim().isNotEmpty ==
                              true
                          ? '${student['roll_number']}'
                          : '—',
                      'G.R. No.',
                      '${student['admission_number']}',
                    ),
                    _infoRow(
                      'Class',
                      '${student['class_name']} ${student['section_name'] ?? ''}',
                      'Attendance',
                      attendanceByStudent[id] ?? '—',
                    ),
                    _infoRow(
                      'Student Name',
                      '${student['first_name']} ${student['last_name']}',
                      'Father / Guardian',
                      '${student['guardian_name'] ?? ''}',
                    ),
                    _infoRow(
                      'Rank',
                      '$rank',
                      'Academic Year',
                      '${exam['academic_year']}',
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey500,
                    width: 0.5,
                  ),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.3),
                    1: pw.FlexColumnWidth(1),
                    2: pw.FlexColumnWidth(1),
                    3: pw.FlexColumnWidth(1),
                    4: pw.FlexColumnWidth(0.7),
                    5: pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    _resultRow(
                      'SUBJECT',
                      'TOTAL',
                      'OBTAINED',
                      '%',
                      'GRADE',
                      'REMARKS',
                      header: true,
                      headerColor: accent,
                    ),
                    for (final subject in _subjects)
                      _resultRow(
                        '${subject['subject_name']}',
                        _num((subject['total_marks'] as num).toDouble()),
                        _num(_obtained(id, subject['subject_id'] as String)),
                        ((_obtained(id, subject['subject_id'] as String) /
                                    (subject['total_marks'] as num)
                                        .toDouble()) *
                                100)
                            .toStringAsFixed(2),
                        _grade(
                          (_obtained(id, subject['subject_id'] as String) /
                                  (subject['total_marks'] as num).toDouble()) *
                              100,
                        ),
                        _remark(
                          _obtained(id, subject['subject_id'] as String) /
                              (subject['total_marks'] as num).toDouble() *
                              100,
                        ),
                      ),
                    _resultRow(
                      'GRAND TOTAL',
                      _num(max),
                      _num(_total(id)),
                      percent.toStringAsFixed(2),
                      _grade(percent),
                      '${_remark(percent)} · RANK $rank',
                      total: true,
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: accent, width: 0.8),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'OVERALL REMARK: ',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                        ),
                      ),
                      pw.Text(
                        _remark(percent),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.5),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'CLASS TEACHER REMARK: ',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 7,
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          '____________________________________________',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'SUBJECT-WISE PERFORMANCE',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Container(
                  height: 118,
                  padding: const pw.EdgeInsets.fromLTRB(5, 4, 5, 2),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 0.4),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      for (var index = 0; index < _subjects.length; index++)
                        pw.Expanded(
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.Text(
                                '${(_obtained(id, _subjects[index]['subject_id'] as String) / (_subjects[index]['total_marks'] as num).toDouble() * 100).toStringAsFixed(0)}%',
                                style: const pw.TextStyle(fontSize: 6),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Container(
                                width: 18,
                                height: 68 *
                                    _ratio(
                                      _obtained(
                                        id,
                                        _subjects[index]['subject_id'] as String,
                                      ),
                                      (_subjects[index]['total_marks'] as num)
                                          .toDouble(),
                                    ),
                                color: graphColors[index],
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                '${_subjects[index]['subject_name']}',
                                maxLines: 2,
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 6),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'GRADES: A+ (80% & Above)  A (70%–79.99%)  B (60%–69.99%)  C (50%–59.99%)  D (40%–49.99%)  F (Below 40%)\n'
                  'REMARKS: Outstanding (80%+)  Excellent (70–79.99%)  Good (60–69.99%)  Satisfactory (50–59.99%)  Do not meet the expectation (below 50%)',
                  style: const pw.TextStyle(fontSize: 6),
                ),
                pw.SizedBox(height: 7),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.SizedBox(height: 23),
                          pw.Container(height: 0.7, color: PdfColors.black),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'PRINCIPAL',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 18),
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.SizedBox(height: 23),
                          pw.Container(height: 0.7, color: PdfColors.black),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'CLASS TEACHER',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 7,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 18),
                    pw.Expanded(
                      child: pw.Column(
                        children: [
                          pw.Container(
                            height: 30,
                            width: 90,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(width: 0.6),
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'SCHOOL STAMP',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 7,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return doc.save();
  }

  Future<Map<String, String>> _attendanceSummaries(
    List<Map<String, Object?>> students,
  ) async {
    if (students.isEmpty) return {};

    final db = await AppDatabase.instance.database;
    final summaries = <String, String>{};
    const batchSize = 900;
    for (var start = 0; start < students.length; start += batchSize) {
      final ids = students
          .skip(start)
          .take(batchSize)
          .map((student) => student['student_id'] as String)
          .toList();
      final placeholders = List.filled(ids.length, '?').join(', ');
      final rows = await db.rawQuery(
        'SELECT student_id, '
        "SUM(CASE WHEN status = 'Present' THEN 1 ELSE 0 END) AS present_days, "
        'COUNT(*) AS recorded_days '
        'FROM attendance WHERE student_id IN ($placeholders) '
        'GROUP BY student_id',
        ids,
      );
      for (final row in rows) {
        summaries[row['student_id'] as String] =
            '${row['present_days']} / ${row['recorded_days']} days';
      }
    }
    return summaries;
  }

  static double _ratio(double value, double total) =>
      total <= 0 ? 0 : (value / total).clamp(0, 1);

  List<PdfColor> _subjectGraphColors(String studentId) {
    const palette = [
      0xFF1565C0,
      0xFFC62828,
      0xFF2E7D32,
      0xFFEF6C00,
      0xFF6A1B9A,
      0xFF00838F,
      0xFFAD1457,
      0xFF4E342E,
      0xFF283593,
      0xFF558B2F,
      0xFF4527A0,
      0xFF00695C,
    ];
    final marks = _subjects
        .map(
          (subject) => _obtained(
            studentId,
            subject['subject_id'] as String,
          ),
        )
        .toList(growable: false);
    final percentages = List<double>.generate(
      _subjects.length,
      (index) =>
          marks[index] /
          (_subjects[index]['total_marks'] as num).toDouble() *
          100,
    );
    final groups = List<int>.generate(_subjects.length, (index) => index);

    int root(int index) {
      while (groups[index] != index) {
        groups[index] = groups[groups[index]];
        index = groups[index];
      }
      return index;
    }

    for (var first = 0; first < _subjects.length; first++) {
      for (var second = first + 1; second < _subjects.length; second++) {
        if (marks[first] == marks[second] ||
            (percentages[first] - percentages[second]).abs() < 0.000001) {
          groups[root(second)] = root(first);
        }
      }
    }

    final groupColors = <int, PdfColor>{};
    return List<PdfColor>.generate(_subjects.length, (index) {
      final group = root(index);
      return groupColors.putIfAbsent(
        group,
        () => PdfColor.fromInt(palette[groupColors.length % palette.length]),
      );
    });
  }

  pw.TableRow _infoRow(
    String label1,
    String value1,
    String label2,
    String value2,
  ) => pw.TableRow(
    children: [
      for (final pair in [(label1, value1), (label2, value2)]) ...[
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(
            pair.$1,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(5),
          child: pw.Text(pair.$2, style: const pw.TextStyle(fontSize: 8)),
        ),
      ],
    ],
  );

  pw.TableRow _resultRow(
    String a,
    String b,
    String c,
    String d,
    String e,
    String f, {
    bool header = false,
    bool total = false,
    PdfColor? headerColor,
  }) => pw.TableRow(
    decoration: header
        ? pw.BoxDecoration(color: headerColor ?? PdfColors.grey300)
        : total
        ? const pw.BoxDecoration(color: PdfColors.grey200)
        : null,
    children: [a, b, c, d, e, f]
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: header ? 7 : 8,
                fontWeight: header || total
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
                color: header ? PdfColors.white : PdfColors.black,
              ),
            ),
          ),
        )
        .toList(),
  );

  Future<void> _printTabulation() async {
    if (_subjects.isEmpty || _students.isEmpty) {
      _toast('There are no subjects or students to include.');
      return;
    }
    final exam = _exams.firstWhere((row) => row['exam_id'] == _examId);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(22),
        build: (_) => [
          pw.Text(
            widget.profile.schoolName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'TABULATION SHEET  •  ${exam['exam_name']}  •  Class ${exam['class_name']}',
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.4),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  for (final title in [
                    'Rank',
                    'G.R. No.',
                    'Student',
                    ..._subjects.map(
                      (s) =>
                          '${s['subject_name']}\n/${_num((s['total_marks'] as num).toDouble())}',
                    ),
                    'Total',
                    '%',
                    'Grade',
                    'Remark',
                  ])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        title,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              for (final student in _students)
                pw.TableRow(
                  children:
                      [
                            _complete(student['student_id'] as String)
                                ? '${_rank(student['student_id'] as String)}'
                                : '—',
                            '${student['admission_number']}',
                            '${student['first_name']} ${student['last_name']}',
                            ..._subjects.map(
                              (s) =>
                                  _marks.containsKey(
                                    '${s['subject_id']}:${student['student_id']}',
                                  )
                                  ? _num(
                                      _obtained(
                                        student['student_id'] as String,
                                        s['subject_id'] as String,
                                      ),
                                    )
                                  : 'Incomplete',
                            ),
                            _num(_total(student['student_id'] as String)),
                            _complete(student['student_id'] as String)
                                ? _percent(student['student_id'] as String)
                                      .toStringAsFixed(2)
                                : '',
                            _complete(student['student_id'] as String)
                                ? _grade(
                                    _percent(student['student_id'] as String),
                                  )
                                : '',
                            _complete(student['student_id'] as String)
                                ? _remark(
                                    _percent(student['student_id'] as String),
                                  )
                                : 'Incomplete',
                          ]
                          .map(
                            (value) => pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(
                                value,
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                            ),
                          )
                          .toList(),
                ),
            ],
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'TLC-tabulation-${exam['class_name']}.pdf',
    );
  }

  Future<void> _exportExcel() async {
    if (_examId == null) return;
    final exam = _exams.firstWhere((row) => row['exam_id'] == _examId);
    final workbook = Excel.createExcel();
    final sheet = workbook['Tabulation'];
    sheet.appendRow(
      [
        'Rank',
        'G.R. No.',
        'Student',
        ..._subjects.map(
          (s) => '${s['subject_name']} Total ${s['total_marks']}',
        ),
        'Grand Total',
        'Percentage',
        'Grade',
        'Remark',
      ].map(TextCellValue.new).toList(),
    );
    for (final student in _students) {
      final id = student['student_id'] as String;
      sheet.appendRow(
        [
          _complete(id) ? '${_rank(id)}' : '',
          '${student['admission_number']}',
          '${student['first_name']} ${student['last_name']}',
          ..._subjects.map(
            (s) => _marks.containsKey('${s['subject_id']}:$id')
                ? _num(_obtained(id, s['subject_id'] as String))
                : 'Incomplete',
          ),
          _num(_total(id)),
          _complete(id) ? _percent(id).toStringAsFixed(2) : '',
          _complete(id) ? _grade(_percent(id)) : '',
          _complete(id) ? _remark(_percent(id)) : 'Incomplete',
        ].map(TextCellValue.new).toList(),
      );
    }
    final bytes = workbook.encode();
    if (bytes == null) {
      _toast('The spreadsheet could not be encoded.');
      return;
    }
    await FilePicker.saveFile(
      fileName: 'TLC-tabulation-${exam['class_name']}.xlsx',
      bytes: Uint8List.fromList(bytes),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Widget _tabulationTable() {
    final rankedStudents = _rankedStudents();
    final completeCount = rankedStudents.length;
    final ranks = {
      for (final student in rankedStudents)
        student['student_id'] as String: student['_rank'] as int,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Class tabulation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '$completeCount of ${_students.length} students have complete '
              'marks. Tabulation refreshes automatically every 5 seconds.',
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 460,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    columns: [
                      const DataColumn(label: Text('Rank')),
                      const DataColumn(label: Text('G.R. No.')),
                      const DataColumn(label: Text('Student')),
                      for (final subject in _subjects)
                        DataColumn(
                          numeric: true,
                          label: Text(
                            '${subject['subject_name']}\n'
                            '/ ${_num((subject['total_marks'] as num).toDouble())}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const DataColumn(label: Text('Total')),
                      const DataColumn(label: Text('%')),
                      const DataColumn(label: Text('Grade')),
                      const DataColumn(label: Text('Remark')),
                      const DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      for (final student in _students)
                        _tabulationRow(student, ranks),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Students with incomplete marks are not ranked. Their entered '
              'marks are shown; the total is partial until every subject is '
              'entered.',
            ),
          ),
        ],
      ),
    );
  }

  DataRow _tabulationRow(Map<String, Object?> student, Map<String, int> ranks) {
    final id = student['student_id'] as String;
    final complete = _complete(id);
    final percent = _percent(id);
    return DataRow(
      cells: [
        DataCell(Text('${ranks[id] ?? '—'}')),
        DataCell(Text('${student['admission_number']}')),
        DataCell(
          Text('${student['first_name']} ${student['last_name']}'.trim()),
        ),
        for (final subject in _subjects)
          DataCell(
            Text(
              _marks.containsKey('${subject['subject_id']}:$id')
                  ? _num(_obtained(id, subject['subject_id'] as String))
                  : '—',
            ),
          ),
        DataCell(Text('${_num(_total(id))}${complete ? '' : ' *'}')),
        DataCell(Text(complete ? percent.toStringAsFixed(2) : '—')),
        DataCell(Text(complete ? _grade(percent) : '—')),
        DataCell(Text(complete ? _remark(percent) : '—')),
        DataCell(Text(complete ? 'Complete' : 'Incomplete')),
      ],
    );
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final exam = _exams.where((row) => row['exam_id'] == _examId).firstOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text('Results & Report Cards'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Could not load results: $_error'))
          : _exams.isEmpty
          ? const Center(child: Text('No exam results are available.'))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _examId,
                  decoration: const InputDecoration(
                    labelText: 'Exam / class',
                    border: OutlineInputBorder(),
                  ),
                  items: _exams
                      .map(
                        (e) => DropdownMenuItem(
                          value: e['exam_id'] as String,
                          child: Text(
                            '${e['exam_name']} · Class ${e['class_name']}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _examId = value;
                        _studentId = null;
                        _loading = true;
                      });
                    }
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                if (exam != null && _students.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _studentId,
                    decoration: const InputDecoration(
                      labelText: 'Student report card',
                      border: OutlineInputBorder(),
                    ),
                    items: _students
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['student_id'] as String,
                            child: Text(
                              '${s['admission_number']} · ${s['first_name']} ${s['last_name']}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _studentId = value),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _working ? null : _printCard,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          _working ? 'Preparing…' : 'Print report card',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _working ? null : _printAllCards,
                        icon: const Icon(Icons.group_outlined),
                        label: Text(
                          _working
                              ? 'Preparing…'
                              : 'Print all class report cards',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _printTabulation,
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Print tabulation'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _exportExcel,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Export tabulation to Excel'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_subjects.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No subjects have been added to this examination.',
                        ),
                      ),
                    )
                  else
                    _tabulationTable(),
                ] else if (exam != null)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'No active students match this exam’s class and section. Check the student register or update the exam class / section.',
                    ),
                  ),
              ],
            ),
    );
  }
}

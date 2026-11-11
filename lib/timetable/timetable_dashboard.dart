import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../auth/app_user.dart';
import '../data/app_database.dart';
import '../data/record_id.dart';

class TimetableDashboard extends StatefulWidget {
  final AppUser? user;

  const TimetableDashboard({super.key, this.user});
  @override
  State<TimetableDashboard> createState() => _TimetableDashboardState();
}

class _TimetableDashboardState extends State<TimetableDashboard>
    with SingleTickerProviderStateMixin {
  static const red = Color(0xFFC62828);
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  static const _roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
  static const _monThu = [
    ('08:05', '08:50'),
    ('08:50', '09:30'),
    ('09:30', '10:10'),
    ('10:10', '10:50'),
    ('11:10', '11:50'),
    ('11:50', '12:30'),
    ('12:30', '13:10'),
  ];
  static const _friday = [
    ('08:05', '08:40'),
    ('08:40', '09:15'),
    ('09:15', '09:50'),
    ('09:50', '10:25'),
    ('10:40', '11:15'),
    ('11:15', '11:50'),
    ('11:50', '12:20'),
  ];

  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  List<Map<String, Object?>> _entries = [];
  List<Map<String, Object?>> _exams = [];
  final _teacherFilter = TextEditingController();
  bool get _canEdit =>
      widget.user == null ||
      AppRoles.fullAccessRoles.contains(widget.user!.role);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _teacherFilter.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final db = await AppDatabase.instance.database;
      final allEntries = await db.query(
        'timetable_entries',
        orderBy: 'weekday ASC, start_time ASC',
      );
      final allExams = await db.query('exams', orderBy: 'start_date ASC');
      final user = widget.user;
      if (user?.role == AppRoles.teacher) {
        final scopes = user!.assignedClassSections.toSet();
        final teacherName = user.fullName.trim().toLowerCase();
        _entries = allEntries.where((entry) {
          final key =
              '${entry['class_name']}\u001f${entry['section_name'] ?? ''}';
          return scopes.contains(key) ||
              '${entry['teacher_name']}'.trim().toLowerCase() == teacherName;
        }).toList();
        _exams = allExams.where((exam) {
          final key =
              '${exam['class_name']}\u001f${exam['section_name'] ?? ''}';
          return scopes.contains(key);
        }).toList();
      } else {
        _entries = allEntries;
        _exams = allExams;
      }
    } catch (error) {
      _message('Could not load timetable data: $error');
    }
    if (mounted) setState(() => _loading = false);
  }

  (String, String) _timeSlot(int weekday, int period) =>
      (weekday == 5 ? _friday : _monThu)[period - 1];
  List<(String, String)> _slots(int weekday) =>
      weekday == 5 ? _friday : _monThu;
  String _displayTime((String, String) slot) => '${slot.$1}–${slot.$2}';
  String _normalizeTime(String value) => value.length == 4 ? '0$value' : value;
  int _periodFor(Map<String, Object?> entry, int weekday) {
    final start = _normalizeTime('${entry['start_time']}');
    final end = _normalizeTime('${entry['end_time']}');
    final slots = _slots(weekday);
    final exact = slots.indexWhere(
      (slot) => slot.$1 == start && slot.$2 == end,
    );
    if (exact >= 0) return exact + 1;
    final mins = _minutes(start);
    var nearest = 0;
    var distance = 99999;
    for (var i = 0; i < slots.length; i++) {
      final delta = (_minutes(slots[i].$1) - mins).abs();
      if (delta < distance) {
        distance = delta;
        nearest = i;
      }
    }
    return nearest + 1;
  }

  int _minutes(String value) {
    final parts = value.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  Future<void> _addTimetableEntry({
    Map<String, Object?>? existing,
    String? defaultClass,
    String? defaultSection,
    int? defaultDay,
    int? defaultPeriod,
  }) async {
    if (!_canEdit) return;
    final form = GlobalKey<FormState>();
    final classController = TextEditingController(
      text: existing?['class_name']?.toString() ?? defaultClass ?? '',
    );
    final sectionController = TextEditingController(
      text: existing?['section_name']?.toString() ?? defaultSection ?? '',
    );
    final subjectController = TextEditingController(
      text: existing?['subject']?.toString() ?? '',
    );
    final teacherController = TextEditingController(
      text: existing?['teacher_name']?.toString() ?? '',
    );
    final roomController = TextEditingController(
      text: existing?['room']?.toString() ?? '',
    );
    var weekday = existing?['weekday'] as int? ?? defaultDay ?? 1;
    var period = existing == null
        ? defaultPeriod ?? 1
        : _periodFor(existing, weekday);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null
                ? 'Assign timetable period'
                : 'Edit timetable period',
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: classController,
                      decoration: const InputDecoration(labelText: 'Class'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: sectionController,
                      decoration: const InputDecoration(
                        labelText: 'Section (optional)',
                      ),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: weekday,
                      decoration: const InputDecoration(labelText: 'Day'),
                      items: List.generate(
                        5,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text(_days[index]),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          update(() {
                            weekday = value;
                          });
                        }
                      },
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: period,
                      decoration: const InputDecoration(
                        labelText: 'Period / time',
                      ),
                      items: List.generate(
                        7,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text(
                            '${_roman[index]}  ${_displayTime(_timeSlot(weekday, index + 1))}',
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) update(() => period = value);
                      },
                    ),
                    TextFormField(
                      controller: subjectController,
                      decoration: const InputDecoration(labelText: 'Subject'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: teacherController,
                      decoration: const InputDecoration(labelText: 'Teacher'),
                      validator: _required,
                    ),
                    TextFormField(
                      controller: roomController,
                      decoration: const InputDecoration(
                        labelText: 'Room (optional)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final slot = _timeSlot(weekday, period);
      final className = classController.text.trim();
      final section = sectionController.text.trim();
      final teacher = teacherController.text.trim();
      final conflicts = _entries.where(
        (entry) =>
            entry['entry_id'] != existing?['entry_id'] &&
            entry['weekday'] == weekday &&
            _periodFor(entry, weekday) == period,
      );
      final classBusy = conflicts.any(
        (entry) =>
            entry['class_name'] == className &&
            (entry['section_name'] ?? '') == section,
      );
      final teacherBusy = conflicts.any(
        (entry) =>
            '${entry['teacher_name']}'.toLowerCase() == teacher.toLowerCase(),
      );
      if (classBusy || teacherBusy) {
        _message(
          classBusy
              ? 'That class already has a lesson in this period.'
              : 'That teacher already has a lesson in this period.',
        );
      } else {
        final db = await AppDatabase.instance.database;
        final values = {
          'class_name': className,
          'section_name': section,
          'weekday': weekday,
          'start_time': slot.$1,
          'end_time': slot.$2,
          'subject': subjectController.text.trim(),
          'teacher_name': teacher,
          'room': roomController.text.trim(),
        };
        if (existing == null) {
          await db.insert('timetable_entries', {
            'entry_id': newRecordId(),
            ...values,
            'created_at': DateTime.now().toIso8601String(),
          });
        } else {
          await db.update(
            'timetable_entries',
            values,
            where: 'entry_id = ?',
            whereArgs: [existing['entry_id']],
          );
        }
        _message('Timetable saved.');
        await _loadData();
      }
    }
    classController.dispose();
    sectionController.dispose();
    subjectController.dispose();
    teacherController.dispose();
    roomController.dispose();
  }

  Future<void> _addExam() async {
    if (!_canEdit) return;
    final name = TextEditingController();
    final className = TextEditingController();
    final year = TextEditingController(text: '2026-2027');
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add exam to calendar'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Exam name'),
                  validator: _required,
                ),
                TextFormField(
                  controller: className,
                  decoration: const InputDecoration(labelText: 'Class'),
                  validator: _required,
                ),
                TextFormField(
                  controller: year,
                  decoration: const InputDecoration(labelText: 'Academic year'),
                  validator: _required,
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
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final db = await AppDatabase.instance.database;
      await db.insert('exams', {
        'exam_id': newRecordId(),
        'exam_name': name.text.trim(),
        'class_name': className.text.trim(),
        'section_name': '',
        'start_date': today,
        'end_date': today,
        'academic_year': year.text.trim(),
        'notes': '',
        'created_at': DateTime.now().toIso8601String(),
      });
      await _loadData();
      _message('Exam added to timetable calendar.');
    }
    name.dispose();
    className.dispose();
    year.dispose();
  }

  Future<void> _deleteEntry(String id) async {
    if (!_canEdit) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete timetable entry?'),
        content: const Text('This permanently removes the lesson assignment.'),
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
    if (confirmed == true) {
      final db = await AppDatabase.instance.database;
      await db.delete(
        'timetable_entries',
        where: 'entry_id = ?',
        whereArgs: [id],
      );
      await _loadData();
    }
  }

  Future<void> _printGrid(
    String title,
    List<Map<String, Object?>> entries,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'THE LEARNING CIRCLE SECONDARY SCHOOL',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
            ),
            pw.Text('Time-Table 2026–2027', textAlign: pw.TextAlign.center),
            pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(width: 0.45),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.1),
                for (var i = 1; i < 11; i++) i: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children:
                      [
                            'DAYS',
                            'ASSEMBLY\n07:55-08:05',
                            for (var i = 0; i < 7; i++)
                              '${_roman[i]}\nM-Th ${_displayTime(_monThu[i])}\nFri ${_displayTime(_friday[i])}',
                            'BREAK\nM-Th 10:50-11:10\nFri 10:25-10:40',
                            'DIARY\nM-Th 01:10-01:30\nFri 12:20-12:30',
                          ]
                          .map(
                            (s) => pw.Padding(
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(
                                s,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 6,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                for (var day = 1; day <= 5; day++)
                  pw.TableRow(
                    children:
                        [
                              _days[day - 1],
                              'Assembly',
                              ...List.generate(
                                7,
                                (i) => _subjectAt(entries, day, i + 1),
                              ),
                              day == 5
                                  ? 'Break 10:25-10:40'
                                  : 'Break 10:50-11:10',
                              'Diary',
                            ]
                            .map(
                              (s) => pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  s,
                                  textAlign: pw.TextAlign.center,
                                  style: const pw.TextStyle(fontSize: 6),
                                ),
                              ),
                            )
                            .toList(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'TLC-timetable.pdf',
    );
  }

  String _subjectAt(List<Map<String, Object?>> entries, int day, int period) {
    final row = entries
        .where(
          (entry) =>
              entry['weekday'] == day && _periodFor(entry, day) == period,
        )
        .firstOrNull;
    if (row == null) return '';
    final teacher = row['teacher_name']?.toString() ?? '';
    return '${row['subject']}\n$teacher';
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F7F7),
    appBar: AppBar(
      backgroundColor: red,
      foregroundColor: Colors.white,
      title: const Text('Time-Table 2026–2027'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loadData,
          icon: const Icon(Icons.refresh),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(icon: Icon(Icons.class_), text: 'Class Timetable'),
          Tab(icon: Icon(Icons.person), text: 'Teachers Timetable'),
          Tab(icon: Icon(Icons.event_note), text: 'Exams'),
        ],
      ),
    ),
    floatingActionButton: _canEdit
        ? AnimatedBuilder(
            animation: _tabs,
            builder: (context, child) => FloatingActionButton.extended(
              backgroundColor: red,
              foregroundColor: Colors.white,
              onPressed: _tabs.index == 2
                  ? _addExam
                  : () => _addTimetableEntry(),
              icon: const Icon(Icons.add),
              label: Text(_tabs.index == 2 ? 'Add Exam' : 'Assign Period'),
            ),
          )
        : null,
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(
            controller: _tabs,
            children: [
              _classTimetables(),
              _teacherTimetables(),
              _examTimetable(),
            ],
          ),
  );

  Widget _classTimetables() {
    final keys =
        _entries
            .map(
              (entry) =>
                  '${entry['class_name']}\u001f${entry['section_name'] ?? ''}',
            )
            .toSet()
            .toList()
          ..sort();
    if (keys.isEmpty) {
      return const Center(
        child: Text(
          'No class timetable entries yet. Use Assign Period to begin.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final key in keys) ...[
          Builder(
            builder: (context) {
              final parts = key.split('\u001f');
              final label =
                  'Class ${parts[0]}${parts[1].isEmpty ? '' : ' - ${parts[1]}'}';
              final entries = _entries
                  .where(
                    (e) =>
                        e['class_name'] == parts[0] &&
                        (e['section_name'] ?? '') == parts[1],
                  )
                  .toList();
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        'Assembly · seven periods · Break · Diary',
                      ),
                      trailing: IconButton(
                        tooltip: 'Print timetable',
                        onPressed: () => _printGrid(label, entries),
                        icon: const Icon(Icons.print_outlined),
                      ),
                    ),
                    _grid(
                      entries,
                      label,
                      isTeacher: false,
                      defaultClass: parts[0],
                      defaultSection: parts[1],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _teacherTimetables() {
    final teachers =
        _entries
            .map((e) => '${e['teacher_name']}')
            .where((name) => name.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final query = _teacherFilter.text.trim().toLowerCase();
    final scopedTeachers = widget.user?.role == AppRoles.teacher
        ? (teachers.any(
                (name) =>
                    name.trim().toLowerCase() ==
                    widget.user!.fullName.trim().toLowerCase(),
              )
              ? [widget.user!.fullName]
              : <String>[])
        : teachers;
    final visible = scopedTeachers
        .where((name) => query.isEmpty || name.toLowerCase().contains(query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _teacherFilter,
            decoration: const InputDecoration(
              labelText: 'Search teacher',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No teacher timetable entries found.'))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final teacher in visible)
                      Builder(
                        builder: (context) {
                          final entries = _entries
                              .where(
                                (e) =>
                                    '${e['teacher_name']}'
                                        .trim()
                                        .toLowerCase() ==
                                    teacher.trim().toLowerCase(),
                              )
                              .toList();
                          return Card(
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(
                                    teacher,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Teacher weekly schedule',
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Print timetable',
                                    onPressed: () => _printGrid(
                                      'Teacher: $teacher',
                                      entries,
                                    ),
                                    icon: const Icon(Icons.print_outlined),
                                  ),
                                ),
                                _grid(entries, teacher, isTeacher: true),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _grid(
    List<Map<String, Object?>> entries,
    String group, {
    required bool isTeacher,
    String? defaultClass,
    String? defaultSection,
  }) {
    final headers = [
      'DAY',
      'ASSEMBLY\n07:55–08:05',
      'I\n08:05–08:50\nFri 08:05–08:40',
      'II\n08:50–09:30\nFri 08:40–09:15',
      'III\n09:30–10:10\nFri 09:15–09:50',
      'IV\n10:10–10:50\nFri 09:50–10:25',
      'BREAK\n10:50–11:10',
      'V\n11:10–11:50\nFri 10:40–11:15',
      'VI\n11:50–12:30\nFri 11:15–11:50',
      'VII\n12:30–01:10\nFri 11:50–12:20',
      'DIARY\n01:10–01:30',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 8,
        headingRowHeight: 76,
        dataRowMinHeight: 58,
        dataRowMaxHeight: 72,
        columns: headers
            .map(
              (header) => DataColumn(
                label: SizedBox(
                  width: header == 'DAY' ? 95 : 86,
                  child: Text(
                    header,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
        rows: [
          for (var day = 1; day <= 5; day++)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    _days[day - 1],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const DataCell(
                  Center(
                    child: Text(
                      'Assembly',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                for (var period = 1; period <= 4; period++)
                  _periodCell(
                    entries,
                    day,
                    period,
                    isTeacher,
                    defaultClass,
                    defaultSection,
                  ),
                DataCell(
                  Center(
                    child: Text(
                      day == 5 ? '10:25–10:40\nBreak' : '10:50–11:10\nBreak',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                for (var period = 5; period <= 7; period++)
                  _periodCell(
                    entries,
                    day,
                    period,
                    isTeacher,
                    defaultClass,
                    defaultSection,
                  ),
                DataCell(
                  Center(
                    child: Text(
                      day == 5 ? '12:20–12:30\nDiary' : '01:10–01:30\nDiary',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  DataCell _periodCell(
    List<Map<String, Object?>> entries,
    int day,
    int period,
    bool isTeacher,
    String? defaultClass,
    String? defaultSection,
  ) {
    final entry = entries
        .where((row) => row['weekday'] == day && _periodFor(row, day) == period)
        .firstOrNull;
    if (entry == null) {
      return DataCell(
        InkWell(
          onTap: _canEdit
              ? () => _addTimetableEntry(
                  defaultClass: isTeacher ? null : defaultClass,
                  defaultSection: isTeacher ? null : defaultSection,
                  defaultDay: day,
                  defaultPeriod: period,
                )
              : null,
          child: const Center(
            child: Icon(Icons.add, size: 15, color: Colors.black26),
          ),
        ),
      );
    }
    return DataCell(
      InkWell(
        onTap: _canEdit ? () => _addTimetableEntry(existing: entry) : null,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${entry['subject']}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isTeacher
                    ? 'Class ${entry['class_name']} ${entry['section_name'] ?? ''}'
                    : '${entry['teacher_name']}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8),
              ),
              if (_canEdit)
                IconButton(
                  tooltip: 'Delete period',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    maxHeight: 22,
                    maxWidth: 22,
                  ),
                  onPressed: () => _deleteEntry(entry['entry_id'] as String),
                  icon: const Icon(Icons.close, size: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _examTimetable() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      if (_exams.isEmpty)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Text('No exams have been added to the calendar.'),
          ),
        ),
      for (final exam in _exams)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.event)),
            title: Text('${exam['exam_name']}'),
            subtitle: Text(
              'Class ${exam['class_name']} · ${exam['academic_year']} · ${exam['start_date']}',
            ),
          ),
        ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/app_user.dart';
import '../data/app_database.dart';
import '../data/record_id.dart';
import '../school_profile.dart';

class ExaminationsPage extends StatefulWidget {
  final AppUser user;
  final SchoolProfile profile;

  const ExaminationsPage({
    super.key,
    required this.user,
    required this.profile,
  });

  @override
  State<ExaminationsPage> createState() => _ExaminationsPageState();
}

class _ExaminationsPageState extends State<ExaminationsPage> {
  List<Map<String, Object?>> _exams = [];
  List<(String, String)> _classSections = [];
  final Map<String, List<Map<String, Object?>>> _subjects = {};
  bool _loading = true;
  String? _error;

  bool get _canManage => AppRoles.fullAccessRoles.contains(widget.user.role);
  bool get _canSetUpExams => _canManage || widget.user.role == AppRoles.teacher;
  Set<String> get _classScope => widget.user.assignedClassSections.toSet();
  String _classSectionKey(String className, String sectionName) =>
      '${className.trim()}\u001f${sectionName.trim()}';

  bool _examInScope(Map<String, Object?> exam) => _classScope.contains(
    _classSectionKey(
      exam['class_name'] as String,
      (exam['section_name'] as String?) ?? '',
    ),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final exams = await db.query('exams', orderBy: 'start_date DESC');
      final filtered = _canManage ? exams : exams.where(_examInScope).toList();
      final studentRows = await db.query(
        'students',
        columns: ['class_name', 'section_name'],
        where: "TRIM(class_name) <> '' AND (date_of_removal IS NULL OR TRIM(date_of_removal) = '')",
      );
      final classSectionsByKey = <String, (String, String)>{};
      for (final student in studentRows) {
        final className = (student['class_name'] as String).trim();
        final sectionName = ((student['section_name'] as String?) ?? '').trim();
        final key = _classSectionKey(className, sectionName);
        if (_canManage || _classScope.contains(key)) {
          classSectionsByKey[key] = (className, sectionName);
        }
      }
      final classSections = classSectionsByKey.values.toList()
        ..sort((a, b) {
          final classOrder = a.$1.compareTo(b.$1);
          return classOrder != 0 ? classOrder : a.$2.compareTo(b.$2);
        });
      final subjects = <String, List<Map<String, Object?>>>{};
      for (final exam in filtered) {
        final id = exam['exam_id'] as String;
        subjects[id] = await db.query(
          'exam_subjects',
          where: 'exam_id = ?',
          whereArgs: [id],
          orderBy: 'subject_name COLLATE NOCASE',
        );
      }
      if (!mounted) return;
      setState(() {
        _exams = filtered;
        _classSections = classSections;
        _subjects
          ..clear()
          ..addAll(subjects);
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _addExam() async {
    if (_classSections.isEmpty) {
      _toast(
        _canManage
            ? 'Add active students to a class before creating an examination.'
            : 'No active students were found in your assigned classes.',
      );
      return;
    }
    final name = TextEditingController();
    var selectedClassSectionKey = _classSectionKey(
      _classSections.first.$1,
      _classSections.first.$2,
    );
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create examination'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Exam name',
                    hintText: 'For example: Monthly Test 1',
                  ),
                  validator: _required,
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedClassSectionKey,
                  decoration: const InputDecoration(
                    labelText: 'Class / section',
                  ),
                  items: [
                    for (final classSection in _classSections)
                      DropdownMenuItem(
                        value: _classSectionKey(
                          classSection.$1,
                          classSection.$2,
                        ),
                        child: Text(
                          classSection.$2.isEmpty
                              ? classSection.$1
                              : '${classSection.$1} · ${classSection.$2}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) selectedClassSectionKey = value;
                  },
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
      final today = _date(DateTime.now());
      final classSection = _classSections.firstWhere(
        (item) => _classSectionKey(item.$1, item.$2) == selectedClassSectionKey,
      );
      final db = await AppDatabase.instance.database;
      final examId = newRecordId();
      await db.transaction((txn) async {
        await txn.insert('exams', {
          'exam_id': examId,
          'exam_name': name.text.trim(),
          'class_name': classSection.$1,
          'section_name': classSection.$2,
          'start_date': today,
          'end_date': today,
          'academic_year': widget.profile.academicYear,
          'notes': '',
          'created_at': DateTime.now().toIso8601String(),
        });
        final savedSubjects = await txn.query(
          'class_subjects',
          where: 'TRIM(class_name) = TRIM(?)',
          whereArgs: [classSection.$1],
          orderBy: 'subject_name COLLATE NOCASE',
        );
        for (final subject in savedSubjects) {
          await txn.insert('exam_subjects', {
            'subject_id': newRecordId(),
            'exam_id': examId,
            'subject_name': subject['subject_name'],
            'exam_date': today,
            'start_time': '08:00',
            'end_time': '09:00',
            'total_marks': 100,
            'room': '',
          });
        }
      });
      await _load();
    }
    name.dispose();
  }

  Future<void> _changeExamClass(Map<String, Object?> exam) async {
    if (_classSections.isEmpty) return;
    final db = await AppDatabase.instance.database;
    final existingMarks = await db.rawQuery(
      '''
      SELECT COUNT(*) AS result_count
      FROM exam_results r
      JOIN exam_subjects s ON s.subject_id = r.subject_id
      WHERE s.exam_id = ?
      ''',
      [exam['exam_id']],
    );
    if ((existingMarks.first['result_count'] as int) > 0) {
      _toast('The class cannot be changed after marks have been entered.');
      return;
    }

    final currentKey = _classSectionKey(
      exam['class_name'] as String,
      (exam['section_name'] as String?) ?? '',
    );
    var selectedKey =
        _classSections.any(
          (item) => _classSectionKey(item.$1, item.$2) == currentKey,
        )
        ? currentKey
        : _classSectionKey(_classSections.first.$1, _classSections.first.$2);
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change exam class / section'),
        content: DropdownButtonFormField<String>(
          initialValue: selectedKey,
          decoration: const InputDecoration(labelText: 'Class / section'),
          items: [
            for (final classSection in _classSections)
              DropdownMenuItem(
                value: _classSectionKey(classSection.$1, classSection.$2),
                child: Text(
                  classSection.$2.isEmpty
                      ? classSection.$1
                      : '${classSection.$1} · ${classSection.$2}',
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) selectedKey = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final classSection = _classSections.firstWhere(
      (item) => _classSectionKey(item.$1, item.$2) == selectedKey,
    );
    await db.update(
      'exams',
      {'class_name': classSection.$1, 'section_name': classSection.$2},
      where: 'exam_id = ?',
      whereArgs: [exam['exam_id']],
    );
    await _load();
  }

  Future<void> _addSubject(Map<String, Object?> exam) async {
    final name = TextEditingController();
    final total = TextEditingController(text: '100');
    final examId = exam['exam_id'] as String;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add subject to ${exam['exam_name']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Subject name'),
              ),
              TextField(
                controller: total,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Total marks'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(total.text.trim());
              if (name.text.trim().isNotEmpty && value != null && value > 0) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add subject'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final subjectName = name.text.trim();
      final maxMarks = double.parse(total.text.trim());
      final db = await AppDatabase.instance.database;
      await db.insert('class_subjects', {
        'class_subject_id': newRecordId(),
        'class_name': exam['class_name'],
        'subject_name': subjectName,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final startDate =
          (exam['start_date'] as String?) ?? _date(DateTime.now());
      await db.insert('exam_subjects', {
        'subject_id': newRecordId(),
        'exam_id': examId,
        'subject_name': subjectName,
        'exam_date': startDate,
        'start_time': '08:00',
        'end_time': '09:00',
        'total_marks': maxMarks,
        'room': '',
      });
      await _load();
    }
    name.dispose();
    total.dispose();
  }

  Future<void> _editTotal(Map<String, Object?> subject) async {
    final controller = TextEditingController(text: '${subject['total_marks']}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit total marks'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Total marks'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value != null && value > 0) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final value = double.parse(controller.text.trim());
      final db = await AppDatabase.instance.database;
      final existing = await db.query(
        'exam_results',
        where: 'subject_id = ?',
        whereArgs: [subject['subject_id']],
      );
      if (existing.any((row) => (row['marks_obtained'] as num) > value)) {
        _toast('This total is below a mark already entered.');
      } else {
        await db.update(
          'exam_subjects',
          {'total_marks': value},
          where: 'subject_id = ?',
          whereArgs: [subject['subject_id']],
        );
        await _load();
      }
    }
    controller.dispose();
  }

  Future<void> _enterMarks(
    Map<String, Object?> exam,
    Map<String, Object?> subject,
  ) async {
    final db = await AppDatabase.instance.database;
    final students = await db.query(
      'students',
      where: "TRIM(class_name) = TRIM(?) AND TRIM(COALESCE(section_name, '')) = TRIM(?) AND (date_of_removal IS NULL OR TRIM(date_of_removal) = '')",
      whereArgs: [exam['class_name'], exam['section_name'] ?? ''],
      orderBy: 'first_name COLLATE NOCASE, last_name COLLATE NOCASE',
    );
    if (students.isEmpty) {
      _toast(
        'No active students match Class ${exam['class_name']}'
        '${(exam['section_name'] as String? ?? '').trim().isEmpty ? '' : ' · ${exam['section_name']}'}'
        '. Check the student register or change this exam’s class/section.',
      );
      return;
    }
    final saved = await db.query(
      'exam_results',
      where: 'subject_id = ?',
      whereArgs: [subject['subject_id']],
    );
    final values = {
      for (final row in saved)
        row['student_id'] as String: '${row['marks_obtained']}',
    };
    final controllers = <String, TextEditingController>{
      for (final student in students)
        student['student_id'] as String: TextEditingController(
          text: values[student['student_id']] ?? '',
        ),
    };
    final studentIds = students
        .map((student) => student['student_id'] as String)
        .toList(growable: false);
    final focusNodes = {for (final id in studentIds) id: FocusNode()};
    final remarkControllers = <String, TextEditingController>{
      for (final student in students)
        student['student_id'] as String: TextEditingController(
          text: _performanceRemark(
            double.tryParse(values[student['student_id']] ?? '') ?? 0,
            (subject['total_marks'] as num).toDouble(),
          ),
        ),
    };
    final form = GlobalKey<FormState>();
    final total = (subject['total_marks'] as num).toDouble();
    if (!mounted) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      for (final controller in remarkControllers.values) {
        controller.dispose();
      }
      for (final focusNode in focusNodes.values) {
        focusNode.dispose();
      }
      return;
    }
    final commit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Marks: ${subject['subject_name']} (out of ${_mark(total)})',
        ),
        content: SizedBox(
          width: 620,
          height: 520,
          child: Form(
            key: form,
            child: ListView(
              children: [
                for (final (index, student) in students.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${student['first_name']} ${student['last_name']}',
                          ),
                        ),
                        SizedBox(
                          width: 105,
                          child: TextFormField(
                            controller: controllers[student['student_id']],
                            focusNode: focusNodes[student['student_id']],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: index == students.length - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Marks',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter marks';
                              }
                              final mark = double.tryParse(value.trim());
                              if (mark == null || mark < 0 || mark > total) {
                                return '0–${_mark(total)}';
                              }
                              return null;
                            },
                            onChanged: (value) {
                              final mark = double.tryParse(value.trim());
                              final remarkController =
                                  remarkControllers[student['student_id']]!;
                              final remark = mark == null
                                  ? ''
                                  : _performanceRemark(mark, total);
                              if (remarkController.text != remark) {
                                remarkController.text = remark;
                              }
                            },
                            onFieldSubmitted: (_) {
                              if (index + 1 < studentIds.length) {
                                FocusScope.of(context).requestFocus(
                                  focusNodes[studentIds[index + 1]],
                                );
                              } else {
                                FocusScope.of(context).unfocus();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller:
                                remarkControllers[student['student_id']],
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Automatic remark',
                              border: OutlineInputBorder(),
                              isDense: true,
                              helperText: 'Based on subject percentage',
                            ),
                          ),
                        ),
                      ],
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
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Save marks'),
          ),
        ],
      ),
    );
    if (commit == true) {
      await db.transaction((txn) async {
        for (final student in students) {
          final studentId = student['student_id'] as String;
          final mark = double.parse(controllers[studentId]!.text.trim());
          await txn.insert('exam_results', {
            'result_id': newRecordId(),
            'subject_id': subject['subject_id'],
            'student_id': studentId,
            'marks_obtained': mark,
            'remarks': _performanceRemark(mark, total),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      _toast('Marks saved.');
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
    for (final controller in remarkControllers.values) {
      controller.dispose();
    }
    for (final focusNode in focusNodes.values) {
      focusNode.dispose();
    }
  }

  String _performanceRemark(double marks, double total) {
    final percentage = total <= 0 ? 0 : marks / total * 100;
    return percentage >= 80
        ? 'Outstanding'
        : percentage >= 70
        ? 'Excellent'
        : percentage >= 60
        ? 'Good'
        : percentage >= 50
        ? 'Satisfactory'
        : 'Do not meet the expectation';
  }

  Future<void> _manageClassSubjects() async {
    final db = await AppDatabase.instance.database;
    final classRows = await db.rawQuery(
      "SELECT DISTINCT class_name FROM students WHERE TRIM(class_name) <> '' ORDER BY class_name",
    );
    final classes = classRows
        .map((row) => row['class_name'] as String)
        .toList();
    final classController = TextEditingController(
      text: classes.firstOrNull ?? '',
    );
    final subjectController = TextEditingController();
    var subjects = <Map<String, Object?>>[];
    if (classController.text.isNotEmpty) {
      subjects = await db.query(
        'class_subjects',
        where: 'class_name = ?',
        whereArgs: [classController.text],
        orderBy: 'subject_name COLLATE NOCASE',
      );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Subjects by class'),
          content: SizedBox(
            width: 470,
            height: 460,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: classController,
                        decoration: const InputDecoration(
                          labelText: 'Class name',
                        ),
                        onSubmitted: (_) async {
                          subjects = await db.query(
                            'class_subjects',
                            where: 'class_name = ?',
                            whereArgs: [classController.text.trim()],
                            orderBy: 'subject_name COLLATE NOCASE',
                          );
                          update(() {});
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Load subjects',
                      onPressed: () async {
                        subjects = await db.query(
                          'class_subjects',
                          where: 'class_name = ?',
                          whereArgs: [classController.text.trim()],
                          orderBy: 'subject_name COLLATE NOCASE',
                        );
                        update(() {});
                      },
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Subject name',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add subject',
                      onPressed: () async {
                        final name = subjectController.text.trim();
                        final className = classController.text.trim();
                        if (name.isEmpty || className.isEmpty) return;
                        await db.insert('class_subjects', {
                          'class_subject_id': newRecordId(),
                          'class_name': className,
                          'subject_name': name,
                          'created_at': DateTime.now().toIso8601String(),
                        }, conflictAlgorithm: ConflictAlgorithm.ignore);
                        subjectController.clear();
                        subjects = await db.query(
                          'class_subjects',
                          where: 'class_name = ?',
                          whereArgs: [className],
                          orderBy: 'subject_name COLLATE NOCASE',
                        );
                        update(() {});
                      },
                      icon: const Icon(
                        Icons.add_circle,
                        color: Color(0xFFC62828),
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: subjects.isEmpty
                      ? const Center(
                          child: Text('No saved subjects for this class.'),
                        )
                      : ListView(
                          children: [
                            for (final subject in subjects)
                              ListTile(
                                title: Text('${subject['subject_name']}'),
                                onTap: () async {
                                  final edit = TextEditingController(
                                    text: '${subject['subject_name']}',
                                  );
                                  final result = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Rename class subject'),
                                      content: TextField(controller: edit),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            context,
                                            edit.text.trim().isNotEmpty,
                                          ),
                                          child: const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (result == true) {
                                    await db.update(
                                      'class_subjects',
                                      {'subject_name': edit.text.trim()},
                                      where: 'class_subject_id = ?',
                                      whereArgs: [subject['class_subject_id']],
                                    );
                                    subjects = await db.query(
                                      'class_subjects',
                                      where: 'class_name = ?',
                                      whereArgs: [classController.text.trim()],
                                      orderBy: 'subject_name COLLATE NOCASE',
                                    );
                                    update(() {});
                                  }
                                  edit.dispose();
                                },
                                trailing: IconButton(
                                  tooltip: 'Remove subject from class list',
                                  onPressed: () async {
                                    await db.delete(
                                      'class_subjects',
                                      where: 'class_subject_id = ?',
                                      whereArgs: [subject['class_subject_id']],
                                    );
                                    subjects = await db.query(
                                      'class_subjects',
                                      where: 'class_name = ?',
                                      whereArgs: [classController.text.trim()],
                                      orderBy: 'subject_name COLLATE NOCASE',
                                    );
                                    update(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    classController.dispose();
    subjectController.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  String _mark(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(
      title: const Text('Examinations & Marks'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
        if (_canManage)
          IconButton(
            tooltip: 'Manage subjects by class',
            onPressed: _manageClassSubjects,
            icon: const Icon(Icons.subject_outlined),
          ),
        if (_canSetUpExams)
          IconButton(
            tooltip: 'Create exam',
            onPressed: _addExam,
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text('Could not load exams: $_error'))
        : _exams.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No examinations are available for this account.'),
                if (_canSetUpExams) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _addExam,
                    icon: const Icon(Icons.add),
                    label: const Text('Create examination'),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(
                    width: 420,
                    child: Text(
                      'Choose a class, add subjects with their total marks, '
                      'then enter each student’s marks. Existing class '
                      'subjects are added automatically.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (_canSetUpExams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: FilledButton.icon(
                    onPressed: _addExam,
                    icon: const Icon(Icons.add),
                    label: const Text('Create examination'),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                  'Choose an exam, add each subject and its total marks, '
                  'then enter the students’ obtained marks.',
                ),
              ),
              for (final exam in _exams)
                Card(
                  child: ExpansionTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.assignment_outlined),
                    ),
                    title: Text(
                      '${exam['exam_name']} · Class ${exam['class_name']}',
                    ),
                    subtitle: Text(
                      '${exam['academic_year']}  •  ${exam['start_date']}',
                    ),
                    children: [
                      if (_canSetUpExams)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _changeExamClass(exam),
                            icon: const Icon(Icons.drive_file_rename_outline),
                            label: const Text('Change class / section'),
                          ),
                        ),
                      for (final subject
                          in _subjects[exam['exam_id']] ?? const [])
                        ListTile(
                          title: Text('${subject['subject_name']}'),
                          subtitle: Text(
                            'Total: ${_mark((subject['total_marks'] as num).toDouble())} marks',
                          ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              if (_canSetUpExams)
                                IconButton(
                                  tooltip: 'Edit total marks',
                                  onPressed: () => _editTotal(subject),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              FilledButton.tonal(
                                onPressed: () => _enterMarks(exam, subject),
                                child: const Text('Enter marks'),
                              ),
                            ],
                          ),
                        ),
                      if ((_subjects[exam['exam_id']] ?? const []).isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Add subjects and marks to begin.'),
                        ),
                      if (_canSetUpExams)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _addSubject(exam),
                              icon: const Icon(Icons.add),
                              label: const Text('Add subject'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
  );
}

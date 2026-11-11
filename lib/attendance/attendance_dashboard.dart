import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';

class AttendanceDashboard extends StatefulWidget {
  final List<String>? classSectionKeys;

  const AttendanceDashboard({super.key, this.classSectionKeys});

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> {
  final Color red = const Color(0xFFC62828);

  List<String> _classes = [];
  List<Map<String, Object?>> _students = [];
  final Map<String, String> _marks = {};

  String? _selectedClass;
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  String get _dateKey =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-'
      '${_selectedDate.month.toString().padLeft(2, '0')}-'
      '${_selectedDate.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final db = await AppDatabase.instance.database;

      final rows = await db.rawQuery('''
        SELECT DISTINCT class_name, COALESCE(section_name, '') AS section_name
        FROM students ORDER BY class_name, section_name
      ''');

      _classes = rows
          .where((row) {
            if (widget.classSectionKeys == null) return true;
            final key = '${row['class_name']}\u001f${row['section_name']}';
            return widget.classSectionKeys!.contains(key);
          })
          .map((row) => '${row['class_name']}\u001f${row['section_name']}')
          .toList();

      if (_classes.isNotEmpty) {
        _selectedClass ??= _classes.first;
        await _loadStudents();
      } else {
        _students = [];
      }
    } catch (e) {
      _showMessage('Could not load classes: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedClass == null) return;

    setState(() {
      _loading = true;
      _marks.clear();
    });

    try {
      final db = await AppDatabase.instance.database;

      final scope = _selectedClass!.split('\u001f');
      _students = await db.query(
        'students',
        where: "class_name = ? AND COALESCE(section_name, '') = ?",
        whereArgs: [scope[0], scope.length > 1 ? scope[1] : ''],
        orderBy: 'first_name COLLATE NOCASE',
      );

      final saved = await db.query(
        'attendance',
        where: 'attendance_date = ?',
        whereArgs: [_dateKey],
      );

      for (final record in saved) {
        final studentId = record['student_id'].toString();

        final belongsToClass = _students.any(
          (student) => student['student_id'].toString() == studentId,
        );

        if (belongsToClass) {
          _marks[studentId] = record['status'].toString();
        }
      }
    } catch (e) {
      _showMessage('Could not load attendance: $e');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context)
            .copyWith(colorScheme: ColorScheme.fromSeed(seedColor: red)),
        child: child!,
      ),
    );

    if (picked == null) return;

    setState(() => _selectedDate = picked);
    await _loadStudents();
  }

  Future<void> _saveAttendance() async {
    if (_selectedClass == null || _students.isEmpty) {
      _showMessage('No students are available for this class.');
      return;
    }

    if (_marks.isEmpty) {
      _showMessage('Please mark at least one student first.');
      return;
    }

    setState(() => _saving = true);

    try {
      final db = await AppDatabase.instance.database;

      await db.transaction((txn) async {
        for (final student in _students) {
          final id = student['student_id'].toString();
          final status = _marks[id];

          // Unmarked students are not silently marked present.
          if (status == null) continue;

          await txn.insert('attendance', {
            'attendance_id': '${DateTime.now().microsecondsSinceEpoch}_$id',
            'student_id': id,
            'attendance_date': _dateKey,
            'status': status,
            'notes': '',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      if (mounted) {
        _showMessage('Attendance saved successfully.');
      }
    } catch (e) {
      if (mounted) _showMessage('Could not save attendance: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  int _count(String status) =>
      _marks.values.where((value) => value == status).length;

  String _studentName(Map<String, Object?> student) {
    final first = student['first_name']?.toString() ?? '';
    final last = student['last_name']?.toString() ?? '';
    return '$first $last'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final total = _students.length;
    final marked = _marks.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: red,
        foregroundColor: Colors.white,
        title: const Text(
          'Attendance Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadClasses,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadClasses,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _schoolHeader(),
                  const SizedBox(height: 16),
                  _filters(),
                  const SizedBox(height: 16),
                  _summaryCards(total, marked),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Student Attendance',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '$marked / $total marked',
                        style: TextStyle(
                          color: red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_students.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No students found. Add students first '
                          'using the Student Management module.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ..._students.map(_studentCard),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _saveAttendance,
                    style: FilledButton.styleFrom(
                      backgroundColor: red,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save Attendance'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _schoolHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: red.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: red.withValues(alpha: 0.10),
            child: Icon(Icons.fact_check, color: red, size: 30),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THE LEARNING CIRCLE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text('SECONDARY SCHOOL'),
                SizedBox(height: 4),
                Text(
                  "Let's Make It Happens!",
                  style: TextStyle(
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Select Class',
                prefixIcon: Icon(Icons.class_),
                border: OutlineInputBorder(),
              ),
              items: _classes
                  .map(
                    (key) => DropdownMenuItem(
                      value: key,
                      child: Text(_displayClass(key)),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _selectedClass = value);
                await _loadStudents();
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_month),
              label: Text('Attendance Date: $_dateKey'),
            ),
          ],
        ),
      ),
    );
  }

  String _displayClass(String key) {
    final parts = key.split('\u001f');
    return 'Class ${parts.first}${parts.length > 1 && parts[1].isNotEmpty ? ' - ${parts[1]}' : ''}';
  }

  Widget _summaryCards(int total, int marked) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _summary('Total', '$total', Colors.blueGrey),
        _summary('Present', '${_count('Present')}', Colors.green),
        _summary('Absent', '${_count('Absent')}', red),
        _summary('Late', '${_count('Late')}', Colors.orange),
        _summary('Leave', '${_count('Leave')}', Colors.blue),
      ],
    );
  }

  Widget _summary(String title, String value, Color color) {
    return SizedBox(
      width: 112,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(title),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentCard(Map<String, Object?> student) {
    final id = student['student_id'].toString();
    final status = _marks[id];

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: red.withValues(alpha: 0.10),
                  child: Text(
                    _studentName(student).isEmpty
                        ? '?'
                        : _studentName(student)[0].toUpperCase(),
                    style: TextStyle(color: red, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _studentName(student),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Admission No: '
                        '${student['admission_number'] ?? '-'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(
                labelText: 'Attendance Status',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              hint: const Text('Mark attendance'),
              items: const [
                DropdownMenuItem(value: 'Present', child: Text('Present')),
                DropdownMenuItem(value: 'Absent', child: Text('Absent')),
                DropdownMenuItem(value: 'Late', child: Text('Late')),
                DropdownMenuItem(value: 'Leave', child: Text('Leave')),
              ],
              onChanged: (value) {
                setState(() {
                  if (value == null) {
                    _marks.remove(id);
                  } else {
                    _marks[id] = value;
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/app_database.dart';

class ReportCardRequest {
  final String examId;
  final String? studentId;

  const ReportCardRequest({required this.examId, this.studentId});
}

class ReportCardGenerationDialog extends StatefulWidget {
  final List<Map<String, Object?>> exams;
  final String? initialExamId;

  const ReportCardGenerationDialog({
    super.key,
    required this.exams,
    required this.initialExamId,
  });

  @override
  State<ReportCardGenerationDialog> createState() =>
      _ReportCardGenerationDialogState();
}

class _ReportCardGenerationDialogState
    extends State<ReportCardGenerationDialog> {
  String? _examId;
  String? _studentId;
  List<Map<String, Object?>> _students = [];
  bool _singleStudent = false;
  bool _loadingStudents = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _examId =
        widget.exams.any((exam) => exam['exam_id'] == widget.initialExamId)
        ? widget.initialExamId
        : widget.exams.first['exam_id'] as String;
    _loadStudents(_examId!);
  }

  Future<void> _loadStudents(String examId) async {
    final exam = widget.exams.firstWhere((row) => row['exam_id'] == examId);
    try {
      final db = await AppDatabase.instance.database;
      final students = await db.query(
        'students',
        where: "TRIM(class_name) = TRIM(?) AND TRIM(COALESCE(section_name, '')) = TRIM(?) AND (date_of_removal IS NULL OR TRIM(date_of_removal) = '')",
        whereArgs: [exam['class_name'], exam['section_name'] ?? ''],
        orderBy: 'first_name COLLATE NOCASE, last_name COLLATE NOCASE',
      );
      if (!mounted) return;
      setState(() {
        _students = students;
        _studentId = students.isEmpty
            ? null
            : students.first['student_id'] as String;
        _loadingStudents = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _students = [];
        _studentId = null;
        _loadingStudents = false;
        _error = 'Could not load students for this class: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Generate report cards'),
    content: SizedBox(
      width: 470,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _examId,
            decoration: const InputDecoration(labelText: 'Exam and class'),
            items: [
              for (final exam in widget.exams)
                DropdownMenuItem(
                  value: exam['exam_id'] as String,
                  child: Text(
                    '${exam['exam_name']} - Class ${exam['class_name']}'
                    '${((exam['section_name'] as String?) ?? '').trim().isEmpty ? '' : ' - ${exam['section_name']}'}',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _examId = value;
                _students = [];
                _studentId = null;
                _loadingStudents = true;
              });
              _loadStudents(value);
            },
          ),
          const SizedBox(height: 16),
          const Text('Generate for'),
          const SizedBox(height: 4),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.groups_outlined),
                label: Text('Whole class'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.person_outline),
                label: Text('Single student'),
              ),
            ],
            selected: {_singleStudent},
            onSelectionChanged: (selection) =>
                setState(() => _singleStudent = selection.single),
          ),
          if (!_singleStudent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Students with incomplete marks are skipped after confirmation.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_singleStudent) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(_examId),
              initialValue: _studentId,
              decoration: const InputDecoration(labelText: 'Student'),
              items: [
                for (final student in _students)
                  DropdownMenuItem(
                    value: student['student_id'] as String,
                    child: Text(
                      '${student['admission_number']} - '
                      '${student['first_name']} ${student['last_name']}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _studentId = value),
            ),
          ],
          if (_loadingStudents)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!),
            )
          else if (_students.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('No active students are registered in this class.'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _loadingStudents ||
                _students.isEmpty ||
                (_singleStudent && _studentId == null)
            ? null
            : () => Navigator.pop(
                context,
                ReportCardRequest(
                  examId: _examId!,
                  studentId: _singleStudent ? _studentId : null,
                ),
              ),
        child: const Text('Continue'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';

import 'data/student_roster_pdf.dart';
import 'data/student_excel_importer.dart';
import 'data/student_excel_exporter.dart';
import 'data/student_repository.dart';
import 'data/word_document_exporter.dart';
import 'school_profile.dart';
import 'student.dart';

class StudentsPage extends StatefulWidget {
  final Color primaryColor;
  final SchoolProfile? profile;
  final List<String>? classSectionKeys;
  final List<String>? studentIds;
  final bool canManageRecords;

  const StudentsPage({
    super.key,
    required this.primaryColor,
    this.profile,
    this.classSectionKeys,
    this.studentIds,
    this.canManageRecords = true,
  });

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final StudentRepository _repository = StudentRepository();
  late Future<List<Student>> _students;
  String _searchQuery = '';
  String _selectedClass = 'All Classes';
  String _selectedGender = 'All records';
  String _sortOrder = 'Newest';
  bool _isImporting = false;
  bool _isExporting = false;
  bool _isWordExporting = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _students = _loadStudents();
  }

  Future<List<Student>> _loadStudents() => _repository.getAll(
    classSectionKeys: widget.classSectionKeys,
    studentIds: widget.studentIds,
  );

  void _refresh() {
    setState(() {
      _students = _loadStudents();
    });
  }

  Future<void> _importStudents() async {
    if (!widget.canManageRecords) return;
    setState(() => _isImporting = true);
    try {
      final selectedFiles = await FilePicker.pickFiles(
        dialogTitle: 'Select student register workbook',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (selectedFiles.isEmpty) return;

      final bytes = await selectedFiles.first.readAsBytes();
      final preview = StudentExcelImporter().parse(bytes);
      if (preview.errors.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Workbook needs corrections'),
            content: SizedBox(
              width: 520,
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text('No rows were imported. Review these rows:'),
                  const SizedBox(height: 12),
                  for (final error in preview.errors) Text(error),
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
        return;
      }

      if (preview.students.isEmpty) {
        throw const FormatException(
          'No student records were found under the register headings.',
        );
      }
      if (!mounted) return;

      final shouldImport = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import student register?'),
          content: Text(
            '${preview.students.length} student records are ready to import.'
            '${preview.skippedBlankRows == 0 ? '' : '\n${preview.skippedBlankRows} blank rows will be ignored.'}\n\n'
            'Matching G.R. numbers will be updated. Columns missing from this workbook and blank cells will leave existing values unchanged; non-empty cells replace saved values.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: widget.primaryColor,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import Records'),
            ),
          ],
        ),
      );
      if (shouldImport != true || !mounted) return;

      final counts = await _repository.importStudents(
        preview.students,
        includedFields: preview.includedFields,
        emptyFieldsByAdmissionNumber: preview.emptyFieldsByAdmissionNumber,
      );
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import complete: ${counts.imported} added, '
            '${counts.updated} updated, ${counts.unchanged} unchanged.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Student import failed: $error')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _exportStudents() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final students = _filteredStudents(await _students);
      if (students.isEmpty) {
        if (mounted) _message('There are no student records to export.');
        return;
      }
      final location = await FilePicker.saveFile(
        dialogTitle: 'Export student records',
        fileName: 'TLC_Student_Records.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: StudentExcelExporter.encode(students),
      );
      if (!mounted || location == null) return;
      _message('${students.length} records exported to $location');
    } on Exception catch (error) {
      if (mounted) _message('Student export failed: $error');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _printRoster() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final students = _filteredStudents(await _students);
      if (students.isEmpty) {
        if (mounted) _message('There are no student records to print.');
        return;
      }
      await Printing.layoutPdf(
        name: 'TLC_Student_Register.pdf',
        onLayout: (_) => StudentRosterPdf.build(
          profile: widget.profile ?? SchoolProfile.tlc(),
          students: students,
        ),
      );
    } on Exception catch (error) {
      if (mounted) _message('Student register could not be printed: $error');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _exportStudentsToWord() async {
    if (_isWordExporting) return;
    setState(() => _isWordExporting = true);
    try {
      final students = _filteredStudents(await _students);
      if (students.isEmpty) {
        if (mounted) _message('There are no student records to export.');
        return;
      }
      final profile = widget.profile ?? SchoolProfile.tlc();
      final bytes = WordDocumentExporter.encodeTable(
        profile: profile,
        title: 'Student Register • ${profile.academicYear}',
        headers: const [
          'G.R. Number',
          'Roll No.',
          'Student',
          'Gender',
          'Class',
          'Father / Guardian',
          'Contact',
          'Monthly Fee (PKR)',
        ],
        rows: [
          for (final student in students)
            [
              student.admissionNumber,
              student.rollNumber,
              student.fullName,
              student.gender,
              '${student.className}${student.sectionName.isEmpty ? '' : ' - ${student.sectionName}'}',
              student.guardianName,
              student.guardianPhone,
              student.monthlyFee.toStringAsFixed(2),
            ],
        ],
        landscape: true,
      );
      final location = await FilePicker.saveFile(
        dialogTitle: 'Export student register to Word',
        fileName: 'TLC_Student_Register.docx',
        type: FileType.custom,
        allowedExtensions: const ['docx'],
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        bytes: bytes,
      );
      if (!mounted || location == null) return;
      _message('${students.length} student records exported to $location');
    } on Exception catch (error) {
      if (mounted) _message('Word export failed: $error');
    } finally {
      if (mounted) setState(() => _isWordExporting = false);
    }
  }

  Future<void> _showStudentForm({Student? existing}) async {
    if (!widget.canManageRecords) return;
    final grNumberController = TextEditingController(
      text: existing?.admissionNumber ?? '',
    );
    final rollNumberController = TextEditingController(
      text: existing?.rollNumber ?? '',
    );
    final nameController = TextEditingController(
      text: existing?.studentName ?? '',
    );
    final fatherController = TextEditingController(
      text: existing?.guardianName ?? '',
    );
    final classController = TextEditingController(
      text: existing?.className ?? '',
    );
    final contactController = TextEditingController(
      text: existing?.guardianPhone ?? '',
    );
    final religionController = TextEditingController(
      text: existing?.religion ?? '',
    );
    final birthPlaceController = TextEditingController(
      text: existing?.placeOfBirth ?? '',
    );
    final addressController = TextEditingController(
      text: existing?.address ?? '',
    );
    final previousInstituteController = TextEditingController(
      text: existing?.previousInstitute ?? '',
    );
    final admittedClassController = TextEditingController(
      text: existing?.admittedClass ?? '',
    );
    final removalClassController = TextEditingController(
      text: existing?.classAtRemoval ?? '',
    );
    final causeOfRemovalController = TextEditingController(
      text: existing?.causeOfRemoval ?? '',
    );
    final remarksController = TextEditingController(
      text: existing?.remarks ?? '',
    );
    final monthlyFeeController = TextEditingController(
      text: existing == null ? '0' : existing.monthlyFee.toString(),
    );
    final dateOfBirthController = TextEditingController(
      text: _dateText(existing?.dateOfBirth),
    );
    final dateOfAdmissionController = TextEditingController(
      text: _dateText(existing?.dateOfAdmission),
    );
    final dateOfRemovalController = TextEditingController(
      text: _dateText(existing?.dateOfRemoval),
    );
    final controllers = [
      grNumberController,
      rollNumberController,
      nameController,
      fatherController,
      classController,
      contactController,
      religionController,
      birthPlaceController,
      addressController,
      previousInstituteController,
      admittedClassController,
      removalClassController,
      causeOfRemovalController,
      remarksController,
      monthlyFeeController,
      dateOfBirthController,
      dateOfAdmissionController,
      dateOfRemovalController,
    ];
    final dates = <String, DateTime?>{
      'birth': existing?.dateOfBirth,
      'admission': existing?.dateOfAdmission,
      'removal': existing?.dateOfRemoval,
    };
    final formKey = GlobalKey<FormState>();
    final existingGender = existing?.gender.toLowerCase();
    var selectedGender = existing == null
        ? ''
        : existingGender == 'boy' || existingGender == 'male'
        ? 'Boy'
        : existingGender == 'girl' || existingGender == 'female'
        ? 'Girl'
        : 'Other';

    try {
      final student = await showDialog<Student>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'Add Student' : 'Edit Student'),
            content: SizedBox(
              width: 540,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _field(grNumberController, 'G.R. No.', required: true),
                      _field(rollNumberController, 'Roll No.'),
                      _field(nameController, 'Student Name', required: true),
                      _field(fatherController, "Father's Name", required: true),
                      DropdownButtonFormField<String>(
                        initialValue: selectedGender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Select gender'),
                          ),
                          DropdownMenuItem(value: 'Boy', child: Text('Boy')),
                          DropdownMenuItem(value: 'Girl', child: Text('Girl')),
                          DropdownMenuItem(
                            value: 'Other',
                            child: Text('Other / Not specified'),
                          ),
                        ],
                        validator: (value) => value == null || value.isEmpty
                            ? 'Gender is required.'
                            : null,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedGender = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _field(classController, 'Class', required: true),
                      _dateField(
                        dateOfBirthController,
                        'Date of Birth',
                        dates,
                        'birth',
                        setDialogState,
                      ),
                      _field(birthPlaceController, 'Place of Birth'),
                      _field(religionController, 'Religion'),
                      _field(addressController, 'Address', maxLines: 2),
                      _field(contactController, 'Contact No.'),
                      _dateField(
                        dateOfAdmissionController,
                        'Date of Admission',
                        dates,
                        'admission',
                        setDialogState,
                      ),
                      _field(previousInstituteController, 'Previous Institute'),
                      _field(admittedClassController, 'Admitted Class'),
                      _field(
                        monthlyFeeController,
                        'Individual Monthly Fee',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final fee = double.tryParse(value?.trim() ?? '');
                          if (fee == null || fee < 0) {
                            return 'Enter a valid non-negative fee.';
                          }
                          return null;
                        },
                      ),
                      _dateField(
                        dateOfRemovalController,
                        'Date of Removal',
                        dates,
                        'removal',
                        setDialogState,
                      ),
                      _field(
                        removalClassController,
                        'Class at Time of Removal',
                      ),
                      _field(causeOfRemovalController, 'Cause of Removal'),
                      _field(remarksController, 'Remarks', maxLines: 2),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                ),
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final now = DateTime.now();
                  Navigator.pop(
                    dialogContext,
                    Student(
                      studentId:
                          existing?.studentId ??
                          now.microsecondsSinceEpoch.toString(),
                      admissionNumber: grNumberController.text.trim(),
                      rollNumber: rollNumberController.text.trim(),
                      firstName: nameController.text.trim(),
                      lastName: '',
                      className: classController.text.trim(),
                      sectionName: '',
                      guardianName: fatherController.text.trim(),
                      guardianPhone: contactController.text.trim(),
                      familyNo: existing?.familyNo ?? '',
                      gender: selectedGender,
                      religion: religionController.text.trim(),
                      dateOfBirth: dates['birth'],
                      placeOfBirth: birthPlaceController.text.trim(),
                      address: addressController.text.trim(),
                      dateOfAdmission: dates['admission'],
                      previousInstitute: previousInstituteController.text
                          .trim(),
                      admittedClass: admittedClassController.text.trim(),
                      dateOfRemoval: dates['removal'],
                      classAtRemoval: removalClassController.text.trim(),
                      causeOfRemoval: causeOfRemovalController.text.trim(),
                      remarks: remarksController.text.trim(),
                      monthlyFee: double.parse(
                        monthlyFeeController.text.trim(),
                      ),
                      createdAt: existing?.createdAt ?? now,
                    ),
                  );
                },
                child: Text(existing == null ? 'Save Student' : 'Save Changes'),
              ),
            ],
          ),
        ),
      );

      if (student == null || !mounted) return;
      try {
        if (existing == null) {
          await _repository.save(student);
        } else {
          await _repository.update(student);
        }
        _refresh();
      } on Exception {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save the student. Check the G.R. number and try again.',
            ),
          ),
        );
      }
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  Future<void> _selectDate(
    TextEditingController controller,
    Map<String, DateTime?> dates,
    String key,
    StateSetter setDialogState,
  ) async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: dates[key] ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (selectedDate == null) return;
    setDialogState(() {
      dates[key] = selectedDate;
      controller.text = _dateText(selectedDate);
    });
  }

  Widget _dateField(
    TextEditingController controller,
    String label,
    Map<String, DateTime?> dates,
    String key,
    StateSetter setDialogState,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _selectDate(controller, dates, key, setDialogState),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator:
            validator ??
            (required
                ? (value) => value == null || value.trim().isEmpty
                      ? '$label is required.'
                      : null
                : null),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  String _dateText(DateTime? date) =>
      date == null ? '' : date.toLocal().toIso8601String().split('T').first;

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<Student> _filteredStudents(List<Student> students) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = students.where((student) {
      final matchesSearch =
          query.isEmpty ||
          student.studentName.toLowerCase().contains(query) ||
          student.admissionNumber.toLowerCase().contains(query);
      final matchesClass =
          _selectedClass == 'All Classes' ||
          student.className == _selectedClass;
      final genderGroup = _genderGroup(student.gender);
      final matchesGender = switch (_selectedGender) {
        'Both genders' => genderGroup < 2,
        'Boys' => genderGroup == 0,
        'Girls' => genderGroup == 1,
        _ => true,
      };
      return matchesSearch && matchesClass && matchesGender;
    }).toList();

    filtered.sort((a, b) {
      final genderOrder = _genderGroup(a.gender)
          .compareTo(_genderGroup(b.gender));
      if (genderOrder != 0) return genderOrder;
      switch (_sortOrder) {
        case 'Name A-Z':
          return a.studentName.toLowerCase().compareTo(
            b.studentName.toLowerCase(),
          );
        case 'G.R. No.':
          return a.admissionNumber.toLowerCase().compareTo(
            b.admissionNumber.toLowerCase(),
          );
        case 'Class':
          final classOrder = a.className.toLowerCase().compareTo(
            b.className.toLowerCase(),
          );
          return classOrder != 0
              ? classOrder
              : a.studentName.toLowerCase().compareTo(
                  b.studentName.toLowerCase(),
                );
        default:
          return b.createdAt.compareTo(a.createdAt);
      }
    });
    return filtered;
  }

  int _genderGroup(String gender) {
    final normalized = gender.toLowerCase();
    if (normalized == 'boy' || normalized == 'male') return 0;
    if (normalized == 'girl' || normalized == 'female') return 1;
    return 2;
  }

  Future<void> _confirmDelete(Student student) async {
    if (!widget.canManageRecords) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete student?'),
        content: Text('Delete ${student.studentName} from the records?'),
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
    if (confirmed != true || !mounted) return;
    try {
      await _repository.delete(student.studentId);
      _refresh();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete this student record.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'STUDENT RECORDS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Search, add, and manage student master records.',
                style: TextStyle(color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isExporting ? null : _exportStudents,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(_isExporting ? 'Exporting...' : 'Export Excel'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isPrinting ? null : _printRoster,
                    icon: _isPrinting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined),
                    label: Text(_isPrinting ? 'Preparing...' : 'Print'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isWordExporting ? null : _exportStudentsToWord,
                    icon: _isWordExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.description_outlined),
                    label: Text(
                      _isWordExporting ? 'Preparing...' : 'Export Word',
                    ),
                  ),
                  if (widget.canManageRecords) ...[
                    OutlinedButton.icon(
                      onPressed: _isImporting ? null : _importStudents,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _isImporting ? 'Importing...' : 'Import Excel',
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.primaryColor,
                      ),
                      onPressed: _showStudentForm,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Add Student'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search name or G.R. number',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              SizedBox(
                width: 180,
                child: FutureBuilder<List<Student>>(
                  future: _students,
                  builder: (context, snapshot) {
                    final classes =
                        snapshot.data
                            ?.map((student) => student.className)
                            .toSet()
                            .toList() ??
                        [];
                    classes.sort();
                    final activeClass = classes.contains(_selectedClass)
                        ? _selectedClass
                        : 'All Classes';
                    return DropdownButtonFormField<String>(
                      initialValue: activeClass,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Class filter',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'All Classes',
                          child: Text('All Classes'),
                        ),
                        ...classes.map(
                          (className) => DropdownMenuItem(
                            value: className,
                            child: Text(className),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedClass = value);
                        }
                      },
                    );
                  },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedGender,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'All records',
                      child: Text('All records'),
                    ),
                    DropdownMenuItem(
                      value: 'Both genders',
                      child: Text('Both genders'),
                    ),
                    DropdownMenuItem(value: 'Boys', child: Text('Boys')),
                    DropdownMenuItem(value: 'Girls', child: Text('Girls')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedGender = value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: _sortOrder,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sort by',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Newest', child: Text('Newest')),
                    DropdownMenuItem(
                      value: 'Name A-Z',
                      child: Text('Name A-Z'),
                    ),
                    DropdownMenuItem(
                      value: 'G.R. No.',
                      child: Text('G.R. No.'),
                    ),
                    DropdownMenuItem(value: 'Class', child: Text('Class')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortOrder = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: FutureBuilder<List<Student>>(
              future: _students,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unable to load student records.'),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }
                final students = _filteredStudents(snapshot.data ?? []);
                if (students.isEmpty) {
                  return Center(
                    child: Text(
                      snapshot.data?.isEmpty ?? true
                          ? 'No students added yet.'
                          : 'No students match your search or class filter.',
                    ),
                  );
                }

                final groups = <String, List<Student>>{
                  'Boys': [],
                  'Girls': [],
                  'Other / Not specified': [],
                };
                for (final student in students) {
                  groups[<String>[
                        'Boys',
                        'Girls',
                        'Other / Not specified',
                      ][_genderGroup(student.gender)]]!
                      .add(student);
                }

                var serialNumber = 1;
                return Card(
                  elevation: 0,
                  child: ListView(
                    children: [
                      for (final entry in groups.entries)
                        if (entry.value.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              '${entry.key} (${entry.value.length})',
                              style: TextStyle(
                                color: widget.primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SingleChildScrollView(
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
                              columns: [
                                const DataColumn(
                                  label: Center(child: Text('#')),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('STUDENT')),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('G.R. NO.')),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('ROLL NO.')),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('GENDER')),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('CLASS / SECTION')),
                                ),
                                const DataColumn(
                                  label: Center(
                                    child: Text('PARENT / GUARDIAN'),
                                  ),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('CONTACT')),
                                ),
                                const DataColumn(
                                  label: Center(child: Text('MONTHLY FEE')),
                                ),
                                if (widget.canManageRecords)
                                  const DataColumn(
                                    label: Center(child: Text('ACTIONS')),
                                  ),
                              ],
                              rows: [
                                for (final student in entry.value)
                                  DataRow(
                                    cells: [
                                      DataCell(Text('${serialNumber++}')),
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Text(
                                            student.studentName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(student.admissionNumber)),
                                      DataCell(Text(student.rollNumber)),
                                      DataCell(Text(student.gender)),
                                      DataCell(
                                        Text(
                                          [
                                                student.className,
                                                student.sectionName,
                                              ]
                                              .where(
                                                (value) => value.isNotEmpty,
                                              )
                                              .join(' - '),
                                        ),
                                      ),
                                      DataCell(Text(student.guardianName)),
                                      DataCell(Text(student.guardianPhone)),
                                      DataCell(
                                        Text(
                                          student.monthlyFee.toStringAsFixed(2),
                                        ),
                                      ),
                                      if (widget.canManageRecords)
                                        DataCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Edit student',
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                                onPressed: () =>
                                                    _showStudentForm(
                                                      existing: student,
                                                    ),
                                              ),
                                              IconButton(
                                                tooltip: 'Delete student',
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                                onPressed: () =>
                                                    _confirmDelete(student),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

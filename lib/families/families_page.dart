import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/family_excel_importer.dart';
import '../data/family_repository.dart';

class FamiliesPage extends StatefulWidget {
  const FamiliesPage({super.key});

  @override
  State<FamiliesPage> createState() => _FamiliesPageState();
}

class _FamiliesPageState extends State<FamiliesPage> {
  final FamilyRepository _repository = FamilyRepository();
  late Future<List<FamilyGroup>> _families;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _families = _repository.getFamilies();
  }

  Future<void> _importSiblingFile() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select sibling and family workbook',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (files.isEmpty) return;
      final result = FamilyExcelImporter().parse(
        await files.first.readAsBytes(),
      );
      if (result.errors.isNotEmpty) {
        if (!mounted) return;
        await _showErrors(result.errors);
        return;
      }
      if (result.records.isEmpty) {
        throw const FormatException(
          'No student-family assignments were found in the workbook.',
        );
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import sibling and family numbers?'),
          content: Text(
            '${result.records.length} student assignments are ready to import. '
            'Each row is matched by G.R. No.; the supplied Family No. will be saved for that student. '
            'Rows with an empty Family No. are not allowed, and blank workbook rows are ignored.'
            '${result.skippedBlankRows == 0 ? '' : '\n${result.skippedBlankRows} blank rows will be ignored.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import family numbers'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final counts = await _repository.importSiblingAssignments(
        result.records,
      );
      if (!mounted) return;
      setState(() {
        _families = _repository.getFamilies();
      });
      _message(
        'Import complete: ${counts.updated} updated, '
        '${counts.unchanged} unchanged.',
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Sibling workbook import failed: $error');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showErrors(List<String> errors) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Workbook needs corrections'),
      content: SizedBox(
        width: 540,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'No family assignments were imported. Correct these rows and try again:',
            ),
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

  void _message(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FamilyGroup>>(
    future: _families,
    builder: (context, snapshot) {
      final families = snapshot.data ?? const <FamilyGroup>[];
      final siblingCount = families.fold<int>(
        0,
        (total, family) => total + family.students.length,
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Siblings & Families',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF252B36),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Import your sibling workbook by G.R. No. and Family No. to link parent portals and fee vouchers.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF727B89),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    FilledButton.icon(
                      onPressed: _importing ? null : _importSiblingFile,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        _importing ? 'Importing...' : 'Import sibling file',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_error != null) ...[
                  _InlineError(message: _error!),
                  const SizedBox(height: 12),
                ],
                if (snapshot.hasError)
                  _InlineError(
                    message: 'Family records could not be loaded: ${snapshot.error}',
                    onRetry: () =>
                        setState(() => _families = _repository.getFamilies()),
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(36),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Row(
                    children: [
                      _MetricCard(label: 'Families', value: '${families.length}'),
                      const SizedBox(width: 12),
                      _MetricCard(label: 'Linked students', value: '$siblingCount'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (families.isEmpty)
                    const _EmptyFamilies()
                  else
                    for (final family in families)
                      _FamilyCard(family: family),
                  const SizedBox(height: 12),
                  const Text(
                    'Use columns such as G.R. No., Student Name, Father Name, Class, Family No., and sibling count. Family grouping is based only on the explicit Family No.; students are never grouped by father name alone.',
                    style: TextStyle(
                      color: Color(0xFF687080),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _FamilyCard extends StatelessWidget {
  final FamilyGroup family;

  const _FamilyCard({required this.family});

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE7E9EE)),
    ),
    child: ExpansionTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFBECEC),
        foregroundColor: Color(0xFFC62828),
        child: Icon(Icons.family_restroom_outlined),
      ),
      title: Text(
        'Family ${family.familyNo}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${family.fatherName}  •  ${family.students.length} student(s)',
      ),
      children: [
        for (final student in family.students)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 76, right: 20),
            title: Text(student.fullName),
            subtitle: Text(
              'G.R. ${student.admissionNumber}  •  Class ${student.className}'
              '${student.sectionName.trim().isEmpty ? '' : ' - ${student.sectionName}'}',
            ),
          ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF687080))),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _EmptyFamilies extends StatelessWidget {
  const _EmptyFamilies();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: const Text(
      'No family numbers are assigned yet. Import the sibling workbook to create the family dashboard.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFF687080), fontSize: 12),
    ),
  );
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _InlineError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

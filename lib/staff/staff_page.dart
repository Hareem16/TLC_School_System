import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/staff_excel_importer.dart';
import '../data/staff_repository.dart';
import '../school_profile.dart';
import 'staff_salary_slip_pdf.dart';

class StaffPage extends StatefulWidget {
  final Color primaryColor;
  final SchoolProfile? profile;
  final bool canManageRecords;
  final bool canViewSalary;

  const StaffPage({
    super.key,
    required this.primaryColor,
    this.profile,
    this.canManageRecords = false,
    this.canViewSalary = false,
  });

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  final StaffRepository _repository = StaffRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<StaffMember>> _staff;
  bool _importing = false;
  bool _printingSalarySlip = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _staff = _repository.getAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _staff = _repository.getAll(search: _searchController.text);
  }

  String _staffGroup(StaffMember member) {
    final role = member.role.toLowerCase();
    final normalized = role.replaceAll(RegExp(r'[^a-z]'), '');
    if (role.contains('principal') ||
        role.contains('admin') ||
        normalized.contains('fdo') ||
        role.contains('front desk')) {
      return 'ADMIN';
    }
    if (role.contains('teacher')) return 'TEACHERS';
    if (role.contains('auxiliary') ||
        role.contains('auxilary') ||
        role.contains('auxillary')) {
      return 'AUXILIARY STAFF';
    }
    return 'OTHER STAFF';
  }

  Future<void> _importExcel() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select teacher and staff workbooks',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (files.isEmpty) return;

      final records = <StaffImportRecord>[];
      final errors = <String>[];
      var blankRows = 0;
      for (final file in files) {
        try {
          final result = StaffExcelImporter().parse(await file.readAsBytes());
          records.addAll(result.staff);
          blankRows += result.skippedBlankRows;
          errors.addAll(result.errors.map((error) => '${file.name}: $error'));
        } on Exception catch (error) {
          errors.add('${file.name}: $error');
        }
      }
      if (errors.isNotEmpty) {
        if (!mounted) return;
        await _showErrors(errors);
        return;
      }
      if (records.isEmpty) {
        throw const FormatException('No employee rows were found to import.');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import teachers and staff?'),
          content: Text(
            '${records.length} employee rows are ready. Matching staff records will update changed non-blank values; blank cells preserve saved values.'
            '${blankRows == 0 ? '' : '\n$blankRows blank or repeated rows will be ignored.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import Records'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final counts = await _repository.importStaff(records);
      if (!mounted) return;
      setState(_reload);
      _message(
        'Import complete: ${counts.imported} added, '
        '${counts.updated} updated, ${counts.unchanged} unchanged.',
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Staff import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showErrors(List<String> errors) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Workbook needs review'),
      content: SizedBox(
        width: 600,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('No records were imported. Review the files and rows:'),
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

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generateSalarySlip({
    required List<StaffMember> staffOptions,
    StaffMember? staff,
  }) async {
    if (!widget.canViewSalary || _printingSalarySlip) return;
    final request = await showDialog<_SalarySlipRequest>(
      context: context,
      builder: (context) => _SalarySlipDialog(
        staff: staffOptions,
        initialStaff: staff,
      ),
    );
    if (request == null || !mounted) return;

    setState(() {
      _printingSalarySlip = true;
      _error = null;
    });
    try {
      await Printing.layoutPdf(
        name:
            'TLC_Salary_Slip_${request.staff.employeeNumber}_${request.month.year}-${request.month.month.toString().padLeft(2, '0')}.pdf',
        onLayout: (_) => StaffSalarySlipPdf.build(
          profile: widget.profile ?? SchoolProfile.tlc(),
          staff: request.staff,
          month: request.month,
          unpaidDays: request.unpaidDays,
          otherDeductions: request.otherDeductions,
          bankName: request.bankName,
          bankAccountName: request.bankAccountName,
          bankAccountNumber: request.bankAccountNumber,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Salary slip could not be generated: $error');
      }
    } finally {
      if (mounted) setState(() => _printingSalarySlip = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StaffMember>>(
    future: _staff,
    builder: (context, snapshot) {
      final staff = snapshot.data ?? const <StaffMember>[];
      final totalSalary = staff.fold<double>(
        0,
        (total, member) => total + member.monthlySalary,
      );
      final teachers = staff
          .where((member) => member.role.toLowerCase().contains('teacher'))
          .length;
      final staffGroups = <String, List<StaffMember>>{
        'ADMIN': [],
        'TEACHERS': [],
        'AUXILIARY STAFF': [],
        'OTHER STAFF': [],
      };
      for (final member in staff) {
        staffGroups[_staffGroup(member)]!.add(member);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TEACHERS & STAFF',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Employee register, qualifications, appointment dates, and monthly salary.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF727B89),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.canManageRecords)
                      FilledButton.icon(
                        onPressed: _importing ? null : _importExcel,
                        icon: _importing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _importing ? 'Importing...' : 'Import Excel',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                        ),
                      ),
                    if (widget.canViewSalary)
                      OutlinedButton.icon(
                        onPressed: _printingSalarySlip || staff.isEmpty
                            ? null
                            : () => _generateSalarySlip(staffOptions: staff),
                        icon: _printingSalarySlip
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.receipt_long_outlined),
                        label: Text(
                          _printingSalarySlip
                              ? 'Preparing slip...'
                              : 'Generate Salary Slip',
                        ),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _Notice(message: _error!),
                ],
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 800 ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 100,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _Metric(
                          label: 'Employees',
                          value: '${staff.length}',
                          icon: Icons.people_outline_rounded,
                          color: widget.primaryColor,
                        ),
                        _Metric(
                          label: 'Teachers',
                          value: '$teachers',
                          icon: Icons.school_outlined,
                          color: const Color(0xFF576D91),
                        ),
                        if (widget.canViewSalary)
                          _Metric(
                            label: 'Monthly payroll (listed salaries)',
                            value: 'PKR ${totalSalary.toStringAsFixed(0)}',
                            icon: Icons.payments_outlined,
                            color: const Color(0xFF38805A),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(_reload),
                  decoration: InputDecoration(
                    hintText: 'Search employee or designation',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  _Notice(
                    message:
                        'Employee records could not be loaded: ${snapshot.error}',
                  )
                else if (staff.isEmpty)
                  const _EmptyStaff()
                else
                  Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE7E9EE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in staffGroups.entries)
                          if (entry.value.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                '${entry.key} (${entry.value.length})',
                                style: TextStyle(
                                  color: widget.primaryColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
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
                                  color: Color(0xFF303744),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                                columns: [
                                  const DataColumn(
                                    label: Center(child: Text('S.NO.')),
                                  ),
                                  const DataColumn(
                                    label: Center(child: Text('EMPLOYEE')),
                                  ),
                                  const DataColumn(
                                    label: Center(child: Text('DESIGNATION')),
                                  ),
                                  const DataColumn(
                                    label: Center(
                                      child: Text('FATHER / HUSBAND'),
                                    ),
                                  ),
                                  if (widget.canViewSalary) ...[
                                    const DataColumn(
                                      label: Center(
                                        child: Text('ACADEMIC QUALIFICATION'),
                                      ),
                                    ),
                                    const DataColumn(
                                      label: Center(
                                        child: Text(
                                          'PROFESSIONAL QUALIFICATION',
                                        ),
                                      ),
                                    ),
                                  ],
                                  const DataColumn(
                                    label: Center(child: Text('APPOINTED')),
                                  ),
                                  if (widget.canViewSalary)
                                    const DataColumn(
                                      label: Center(
                                        child: Text('MONTHLY SALARY'),
                                      ),
                                    ),
                                  if (widget.canViewSalary)
                                    const DataColumn(
                                      label: Center(child: Text('SALARY SLIP')),
                                    ),
                                ],
                                rows: [
                                  for (
                                    var index = 0;
                                    index < entry.value.length;
                                    index++
                                  )
                                    _staffRow(
                                      index + 1,
                                      entry.value[index],
                                      staff,
                                    ),
                                ],
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                if (widget.canViewSalary)
                  const Text(
                    'Listed salaries are imported as employee profile data. Salary payment status and payslip history are managed separately.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF727B89)),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  DataRow _staffRow(
    int serialNumber,
    StaffMember member,
    List<StaffMember> staffOptions,
  ) => DataRow(
    cells: [
      DataCell(Text('$serialNumber')),
      DataCell(
        SizedBox(
          width: 180,
          child: Text(
            member.fullName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      DataCell(Text(member.role)),
      DataCell(Text(member.fatherName)),
      if (widget.canViewSalary) ...[
        DataCell(Text(member.academicQualification)),
        DataCell(Text(member.professionalQualification)),
      ],
      DataCell(Text(_dateLabel(member.appointmentDate))),
      if (widget.canViewSalary)
        DataCell(Text('PKR ${member.monthlySalary.toStringAsFixed(0)}')),
      if (widget.canViewSalary)
        DataCell(
          TextButton.icon(
            onPressed: _printingSalarySlip
                ? null
                : () => _generateSalarySlip(
                    staffOptions: staffOptions,
                    staff: member,
                  ),
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Generate'),
          ),
        ),
    ],
  );
}

class _SalarySlipRequest {
  final StaffMember staff;
  final DateTime month;
  final double unpaidDays;
  final double otherDeductions;
  final String bankName;
  final String bankAccountName;
  final String bankAccountNumber;

  const _SalarySlipRequest({
    required this.staff,
    required this.month,
    required this.unpaidDays,
    required this.otherDeductions,
    required this.bankName,
    required this.bankAccountName,
    required this.bankAccountNumber,
  });
}

class _SalarySlipDialog extends StatefulWidget {
  final List<StaffMember> staff;
  final StaffMember? initialStaff;

  const _SalarySlipDialog({
    required this.staff,
    this.initialStaff,
  });

  @override
  State<_SalarySlipDialog> createState() => _SalarySlipDialogState();
}

class _SalarySlipDialogState extends State<_SalarySlipDialog> {
  final _formKey = GlobalKey<FormState>();
  final _unpaidDaysController = TextEditingController(text: '0');
  final _deductionsController = TextEditingController(text: '0');
  final _bankNameController = TextEditingController();
  final _bankAccountNameController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();
  StaffMember? _selectedStaff;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _selectedStaff = widget.initialStaff;
  }

  @override
  void dispose() {
    _unpaidDaysController.dispose();
    _deductionsController.dispose();
    _bankNameController.dispose();
    _bankAccountNameController.dispose();
    _bankAccountNumberController.dispose();
    super.dispose();
  }

  Future<void> _selectMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choose salary month',
    );
    if (selected != null && mounted) {
      setState(() => _month = DateTime(selected.year, selected.month));
    }
  }

  void _submit() {
    final form = _formKey.currentState;
    final employee = _selectedStaff;
    if (form == null || employee == null || !form.validate()) return;
    Navigator.of(context).pop(
      _SalarySlipRequest(
        staff: employee,
        month: _month,
        unpaidDays: double.parse(_unpaidDaysController.text.trim()),
        otherDeductions: double.parse(_deductionsController.text.trim()),
        bankName: _bankNameController.text.trim(),
        bankAccountName: _bankAccountNameController.text.trim(),
        bankAccountNumber: _bankAccountNumberController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Generate salary slip / voucher'),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<StaffMember>(
                initialValue: _selectedStaff,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Employee',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final member in widget.staff)
                    DropdownMenuItem(
                      value: member,
                      child: Text(
                        '${member.fullName} - ${member.role}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (member) =>
                    setState(() => _selectedStaff = member),
                validator: (member) =>
                    member == null ? 'Select an employee.' : null,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _selectMonth,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_monthLabel(_month)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankNameController,
                decoration: const InputDecoration(
                  labelText: 'Bank name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankAccountNameController,
                decoration: const InputDecoration(
                  labelText: 'Bank account name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankAccountNumberController,
                decoration: const InputDecoration(
                  labelText: 'Bank account number (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unpaidDaysController,
                decoration: const InputDecoration(
                  labelText: 'NPD (unpaid days)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final days = double.tryParse(value?.trim() ?? '');
                  final maxDays = DateTime(
                    _month.year,
                    _month.month + 1,
                    0,
                  ).day;
                  if (days == null || days < 0 || days > maxDays) {
                    return 'Enter 0 to $maxDays unpaid days.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deductionsController,
                decoration: const InputDecoration(
                  labelText: 'Other deductions (PKR)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final other = double.tryParse(value?.trim() ?? '');
                  final days = double.tryParse(
                        _unpaidDaysController.text.trim(),
                      ) ??
                      0;
                  final maxDays = DateTime(
                    _month.year,
                    _month.month + 1,
                    0,
                  ).day;
                  final unpaid = _selectedStaff == null || days < 0 || days > maxDays
                      ? 0
                      : _selectedStaff!.monthlySalary / maxDays * days;
                  if (other == null || other < 0) {
                    return 'Enter a non-negative deduction.';
                  }
                  if (_selectedStaff != null &&
                      unpaid + other > _selectedStaff!.monthlySalary) {
                    return 'Total deductions cannot exceed salary.';
                  }
                  return null;
                },
              ),
              if (_selectedStaff != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Basic salary: PKR ${_selectedStaff!.monthlySalary.toStringAsFixed(2)}. '
                    'NPD is prorated using calendar days in the selected month.',
                    style: const TextStyle(
                      color: Color(0xFF687080),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bank details are not in the imported staff records. Fill them above if required; blank fields print as not provided. Printing does not record a salary payment.',
                  style: TextStyle(
                    color: Color(0xFF687080),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Generate and Print'),
      ),
    ],
  );

  String _monthLabel(DateTime month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[month.month - 1]} ${month.year}';
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 25),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF687080)),
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF252B36),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  final String message;

  const _Notice({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F0),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF1CBCB)),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFF9A2222))),
  );
}

class _EmptyStaff extends StatelessWidget {
  const _EmptyStaff();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(30),
    child: Column(
      children: [
        Icon(Icons.people_outline_rounded, size: 34, color: Color(0xFFC62828)),
        SizedBox(height: 10),
        Text(
          'No employee records yet.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          'Import P.T. Teacher, Sindhi Teacher, or STAFF workbooks to populate this register.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF727B89), fontSize: 12),
        ),
      ],
    ),
  );
}

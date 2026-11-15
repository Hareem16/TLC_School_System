import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../accounts/school_accounts_page.dart';
import '../auth/app_user.dart';
import '../data/school_finance_repository.dart';
import '../data/staff_repository.dart';
import '../school_profile.dart';
import '../staff/staff_salary_slip_pdf.dart';

class PayrollPage extends StatefulWidget {
  final SchoolProfile profile;
  final AppUser? user;
  const PayrollPage({super.key, required this.profile, this.user});
  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  final StaffRepository _repository = StaffRepository();
  final SchoolFinanceRepository _financeRepository = SchoolFinanceRepository();
  List<StaffMember> _teachers = [];
  Map<String, SchoolSalaryPayment> _salaryPayments = {};
  final Map<String, TextEditingController> _days = {};
  DateTime _month = DateTime.now();
  bool _loading = true;
  bool _working = false;
  bool get _canRecordPayments {
    final user = widget.user;
    return user != null && AppRoles.fullAccessRoles.contains(user.role);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _days.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final staff = await _repository.getAll();
      _teachers = staff
          .where((member) => member.role.toLowerCase().contains('teacher'))
          .toList(growable: false);
      for (final member in _teachers) {
        _days.putIfAbsent(member.id, () => TextEditingController(text: '0'));
      }
      _salaryPayments = await _financeRepository.getSalaryPayments(_monthLabel);
    } catch (error) {
      _toast('Payroll could not be loaded: $error');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSalaryPayments() async {
    try {
      final payments = await _financeRepository.getSalaryPayments(_monthLabel);
      if (mounted) setState(() => _salaryPayments = payments);
    } catch (error) {
      _toast('Recorded salary payments could not be loaded: $error');
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Choose any date in the salary month',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
      await _loadSalaryPayments();
    }
  }

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;
  double _unpaid(StaffMember member) =>
      double.tryParse(_days[member.id]?.text.trim() ?? '') ?? 0;
  double _deduction(StaffMember member) =>
      member.monthlySalary / _daysInMonth * _unpaid(member);
  String get _monthLabel =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _recordSalaryPayment(StaffMember member) async {
    final actor = widget.user;
    if (actor == null || !_canRecordPayments) {
      _toast('Your account cannot record salary payments.');
      return;
    }

    if (_salaryPayments.containsKey(member.id)) {
      _toast('Salary for ${member.fullName} is already recorded as paid.');
      return;
    }
    final entry = await showDialog<_SalaryPaymentEntry>(
      context: context,
      builder: (context) => _SalaryPaymentDialog(
        teacher: member,
        month: _month,
        daysInMonth: _daysInMonth,
        initialUnpaidDays: _days[member.id]?.text ?? '0',
      ),
    );
    if (entry == null || !mounted) return;
    setState(() => _working = true);
    try {
      final payment = await _financeRepository.recordSalaryPayment(
        staffId: member.id,
        monthKey: _monthLabel,
        deductions: entry.deductions,
        paymentMethod: entry.paymentMethod,
        notes: entry.notes,
        actor: actor,
      );
      if (!mounted) return;
      setState(() {
        _salaryPayments = {..._salaryPayments, member.id: payment};
      });
      _toast(
        '${_money(payment.netSalary)} salary payment recorded for ${member.fullName}.',
      );
    } catch (error) {
      _toast('Salary payment could not be recorded: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openSchoolAccounts() async {
    final user = widget.user;
    if (user == null || !_canRecordPayments) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SchoolAccountsPage(user: user)),
    );
  }

  Future<void> _printSheet() async {
    if (_teachers.isEmpty) {
      _toast('No teacher records were found.');
      return;
    }
    for (final member in _teachers) {
      if (double.tryParse(_days[member.id]!.text.trim()) == null ||
          _unpaid(member) < 0 ||
          _unpaid(member) > _daysInMonth ||
          _deduction(member) > member.monthlySalary) {
        _toast('Check unpaid days for ${member.fullName}.');
        return;
      }
    }
    setState(() => _working = true);
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              widget.profile.schoolName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'TEACHER SALARY SHEET  •  $_monthLabel',
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 14),
            pw.Table(
              border: pw.TableBorder.all(width: 0.45),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.5),
                1: pw.FlexColumnWidth(2.2),
                2: pw.FlexColumnWidth(1.1),
                3: pw.FlexColumnWidth(0.8),
                4: pw.FlexColumnWidth(1.2),
                5: pw.FlexColumnWidth(1.2),
                6: pw.FlexColumnWidth(1.2),
              },
              children: [
                _row([
                  '#',
                  'TEACHER',
                  'DESIGNATION',
                  'UNPAID DAYS',
                  'BASIC SALARY',
                  'DEDUCTION',
                  'NET SALARY',
                ], header: true),
                for (var i = 0; i < _teachers.length; i++)
                  _row([
                    '${i + 1}',
                    _teachers[i].fullName,
                    _teachers[i].role,
                    _days[_teachers[i].id]!.text,
                    _money(_teachers[i].monthlySalary),
                    _money(_deduction(_teachers[i])),
                    _money(
                      _teachers[i].monthlySalary - _deduction(_teachers[i]),
                    ),
                  ]),
              ],
            ),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Prepared by: __________________'),
                pw.Text('Principal: __________________'),
                pw.Text('Authorized signature: __________________'),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Generated salary sheet; no payment is recorded or executed.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'TLC-teacher-payroll-$_monthLabel.pdf',
      );
    } catch (error) {
      _toast('Salary sheet could not be prepared: $error');
    }
    if (mounted) setState(() => _working = false);
  }

  pw.TableRow _row(List<String> values, {bool header = false}) => pw.TableRow(
    decoration: header
        ? const pw.BoxDecoration(color: PdfColors.grey300)
        : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: header ? 7 : 8,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(),
  );

  Future<void> _printSlip(StaffMember member) async {
    final days = TextEditingController(text: _days[member.id]?.text ?? '0');
    final other = TextEditingController(text: '0');
    final bankName = TextEditingController();
    final accountName = TextEditingController(text: member.fullName);
    final accountNumber = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Salary slip · ${member.fullName}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: days,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Unpaid days (max $_daysInMonth)',
                ),
              ),
              TextField(
                controller: other,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Other deductions (PKR)',
                ),
              ),
              TextField(
                controller: bankName,
                decoration: const InputDecoration(
                  labelText: 'Bank name (optional)',
                ),
              ),
              TextField(
                controller: accountName,
                decoration: const InputDecoration(
                  labelText: 'Account name (optional)',
                ),
              ),
              TextField(
                controller: accountNumber,
                decoration: const InputDecoration(
                  labelText: 'Account number (optional)',
                ),
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Prepare PDF'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        final bytes = await StaffSalarySlipPdf.build(
          profile: widget.profile,
          staff: member,
          month: _month,
          unpaidDays: double.parse(days.text),
          otherDeductions: double.parse(other.text),
          bankName: bankName.text,
          bankAccountName: accountName.text,
          bankAccountNumber: accountNumber.text,
        );
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: 'TLC-salary-slip-${member.employeeNumber}-$_monthLabel.pdf',
        );
      } catch (error) {
        _toast('Salary slip could not be prepared: $error');
      }
    }
    days.dispose();
    other.dispose();
    bankName.dispose();
    accountName.dispose();
    accountNumber.dispose();
  }

  String _money(double value) => 'Rs. ${value.toStringAsFixed(2)}';
  String _teacherSubtitle(StaffMember teacher) {
    final payment = _salaryPayments[teacher.id];
    final estimate =
        '${teacher.role} · ${_money(teacher.monthlySalary)} per month · '
        'Estimated net ${_money(teacher.monthlySalary - _deduction(teacher))}';
    return payment == null
        ? estimate
        : '$estimate\nPaid ${_money(payment.netSalary)} via ${payment.paymentMethod}';
  }

  void _toast(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(
      title: const Text('Teacher Payroll'),
      actions: [
        IconButton(
          onPressed: _canRecordPayments ? _openSchoolAccounts : null,
          tooltip: 'School Accounts',
          icon: const Icon(Icons.account_balance_wallet_outlined),
        ),
        IconButton(
          onPressed: _pickMonth,
          icon: const Icon(Icons.calendar_month),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Salary month: $_monthLabel',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickMonth,
                        icon: const Icon(Icons.edit_calendar),
                        label: const Text('Change month'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _working ? null : _printSheet,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Print salary sheet'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_teachers.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No teacher staff records found.'),
                  ),
                ),
              for (final teacher in _teachers)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(teacher.fullName),
                    subtitle: Text(_teacherSubtitle(teacher)),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 104,
                          child: TextField(
                            controller: _days[teacher.id],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Unpaid days',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (_salaryPayments.containsKey(teacher.id))
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Chip(
                              avatar: Icon(Icons.check_circle, size: 18),
                              label: Text('Paid'),
                            ),
                          )
                        else if (_canRecordPayments)
                          IconButton(
                            tooltip: 'Record salary payment',
                            onPressed: _working
                                ? null
                                : () => _recordSalaryPayment(teacher),
                            icon: const Icon(Icons.payments_outlined),
                          ),
                        IconButton(
                          tooltip: 'Generate salary slip',
                          onPressed: () => _printSlip(teacher),
                          icon: const Icon(Icons.receipt_long_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Use “Record salary payment” to add a paid salary to School Accounts. This records the payment only; it does not transfer money.',
                ),
              ),
            ],
          ),
  );
}

class _SalaryPaymentDialog extends StatefulWidget {
  final StaffMember teacher;
  final DateTime month;
  final int daysInMonth;
  final String initialUnpaidDays;

  const _SalaryPaymentDialog({
    required this.teacher,
    required this.month,
    required this.daysInMonth,
    required this.initialUnpaidDays,
  });

  @override
  State<_SalaryPaymentDialog> createState() => _SalaryPaymentDialogState();
}

class _SalaryPaymentDialogState extends State<_SalaryPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _unpaidDays;
  final TextEditingController _otherDeductions = TextEditingController(
    text: '0',
  );
  final TextEditingController _notes = TextEditingController();
  String _paymentMethod = 'Cash';

  @override
  void initState() {
    super.initState();
    _unpaidDays = TextEditingController(text: widget.initialUnpaidDays);
  }

  @override
  void dispose() {
    _unpaidDays.dispose();
    _otherDeductions.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _validateAmount(String? value, {required double maximum}) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null || !amount.isFinite || amount < 0 || amount > maximum) {
      return 'Enter a value from 0 to ${maximum.toStringAsFixed(2)}.';
    }
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final days = double.parse(_unpaidDays.text.trim());
    final otherDeductions = double.parse(_otherDeductions.text.trim());
    final absenceDeduction =
        widget.teacher.monthlySalary / widget.daysInMonth * days;
    final deductions =
        ((absenceDeduction + otherDeductions) * 100).round() / 100;
    if (deductions > widget.teacher.monthlySalary) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Deductions cannot exceed salary.')),
      );
      return;
    }
    Navigator.pop(
      context,
      _SalaryPaymentEntry(
        deductions: deductions,
        paymentMethod: _paymentMethod,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Record salary · ${widget.teacher.fullName}'),
    content: SizedBox(
      width: 380,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Salary month: ${widget.month.year}-${widget.month.month.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _unpaidDays,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Unpaid days (max ${widget.daysInMonth})',
                ),
                validator: (value) => _validateAmount(
                  value,
                  maximum: widget.daysInMonth.toDouble(),
                ),
              ),
              TextFormField(
                controller: _otherDeductions,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Other deductions (PKR)',
                ),
                validator: (value) => _validateAmount(
                  value,
                  maximum: widget.teacher.monthlySalary,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(
                    value: 'Bank transfer',
                    child: Text('Bank transfer'),
                  ),
                  DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _paymentMethod = value);
                },
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Text(
                'This records a salary payment in the app; it will not transfer money.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Record as paid')),
    ],
  );
}

class _SalaryPaymentEntry {
  final double deductions;
  final String paymentMethod;
  final String notes;

  const _SalaryPaymentEntry({
    required this.deductions,
    required this.paymentMethod,
    required this.notes,
  });
}

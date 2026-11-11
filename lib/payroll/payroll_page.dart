import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/staff_repository.dart';
import '../school_profile.dart';
import '../staff/staff_salary_slip_pdf.dart';

class PayrollPage extends StatefulWidget {
  final SchoolProfile profile;
  const PayrollPage({super.key, required this.profile});
  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  final StaffRepository _repository = StaffRepository();
  List<StaffMember> _teachers = [];
  final Map<String, TextEditingController> _days = {};
  DateTime _month = DateTime.now();
  bool _loading = true;
  bool _working = false;

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
    } catch (error) {
      _toast('Payroll could not be loaded: $error');
    }
    if (mounted) setState(() => _loading = false);
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
    }
  }

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;
  double _unpaid(StaffMember member) =>
      double.tryParse(_days[member.id]?.text.trim() ?? '') ?? 0;
  double _deduction(StaffMember member) =>
      member.monthlySalary / _daysInMonth * _unpaid(member);
  String get _monthLabel =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

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
                    subtitle: Text(
                      '${teacher.role} · ${_money(teacher.monthlySalary)} per month · Estimated net ${_money(teacher.monthlySalary - _deduction(teacher))}',
                    ),
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
                  'Salary sheets and slips calculate deductions and do not record payments.',
                ),
              ),
            ],
          ),
  );
}

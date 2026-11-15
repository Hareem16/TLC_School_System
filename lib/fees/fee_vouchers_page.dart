import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../auth/app_user.dart';
import '../data/fee_repository.dart';
import '../data/fee_excel_exporter.dart';
import '../school_profile.dart';
import 'fee_ledger_pdf.dart';
import 'fee_receipt_pdf.dart';
import 'fee_voucher_pdf.dart';

enum _FeeExportPeriod { month, date, week, year, session }

enum _FeeExportStatus { all, paid, unpaid, partialPaid, outstandingDues }

class _FeeExportSelection {
  final _FeeExportPeriod period;
  final _FeeExportStatus status;

  const _FeeExportSelection(this.period, this.status);
}

class FeeVouchersPage extends StatefulWidget {
  final AppUser user;
  final SchoolProfile profile;
  final Color primaryColor;
  final List<String>? allowedStudentIds;
  final bool canManageCharges;
  final bool canAcceptPayments;

  const FeeVouchersPage({
    super.key,
    required this.user,
    required this.profile,
    required this.primaryColor,
    this.allowedStudentIds,
    this.canManageCharges = true,
    this.canAcceptPayments = true,
  });

  @override
  State<FeeVouchersPage> createState() => _FeeVouchersPageState();
}

class _FeeVouchersPageState extends State<FeeVouchersPage> {
  final FeeRepository _repository = FeeRepository();
  final TextEditingController _searchController = TextEditingController();
  late DateTime _month;
  late Future<List<FeeCharge>> _charges;
  String? _error;
  bool _generating = false;
  bool _exporting = false;
  bool _printing = false;

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _canReversePayments => widget.user.role == AppRoles.administrator;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _loadCharges();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadCharges() {
    _charges = _repository.getMonthlyCharges(
      _monthKey,
      search: _searchController.text,
      studentIds: widget.allowedStudentIds,
    );
  }

  Future<void> _selectMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choose a month',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _month = DateTime(selected.year, selected.month);
      _loadCharges();
    });
  }

  Future<void> _generateCharges() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final created = await _repository.createMonthlyCharges(_monthKey);
      if (!mounted) return;
      setState(() {
        _generating = false;
        _loadCharges();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            created == 0
                ? 'No new charges created. Set student monthly fees first, or charges already exist.'
                : '$created monthly student charges created.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = 'Monthly charges could not be created: $error';
        });
      }
    }
  }

  Future<_FeeExportSelection?> _selectExportOptions() async {
    var period = _FeeExportPeriod.month;
    var status = _FeeExportStatus.all;
    return showDialog<_FeeExportSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Export fees and vouchers'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<_FeeExportPeriod>(
                initialValue: period,
                decoration: const InputDecoration(labelText: 'Period'),
                items: const [
                  DropdownMenuItem(
                    value: _FeeExportPeriod.month,
                    child: Text('Month wise'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportPeriod.date,
                    child: Text('Date wise'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportPeriod.week,
                    child: Text('Week wise'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportPeriod.year,
                    child: Text('Year wise'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportPeriod.session,
                    child: Text('Session wise (April–March)'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => period = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(switch (period) {
                  _FeeExportPeriod.month =>
                    'Choose a fee month to include all charges for that month.',
                  _FeeExportPeriod.date =>
                    'Choose one date to include charges created on that date.',
                  _FeeExportPeriod.week =>
                    'Choose any day; the report will cover Monday through Sunday.',
                  _FeeExportPeriod.year =>
                    'Choose any date in the calendar year to include its fee months.',
                  _FeeExportPeriod.session =>
                    'Choose any date; the session runs from April through March.',
                }, style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_FeeExportStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Payment status'),
                items: const [
                  DropdownMenuItem(
                    value: _FeeExportStatus.all,
                    child: Text('All statuses'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportStatus.paid,
                    child: Text('Paid'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportStatus.unpaid,
                    child: Text('Unpaid'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportStatus.partialPaid,
                    child: Text('Partial paid'),
                  ),
                  DropdownMenuItem(
                    value: _FeeExportStatus.outstandingDues,
                    child: Text('Outstanding dues'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => status = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _FeeExportSelection(period, status)),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCharges() async {
    if (_exporting) return;
    final selection = await _selectExportOptions();
    if (selection == null || !mounted) return;

    DateTime? month;
    DateTimeRange? range;
    DateTime? monthRangeStart;
    DateTime? monthRangeEnd;
    String? sessionLabel;
    if (selection.period == _FeeExportPeriod.month) {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Choose fee month',
      );
      if (selectedDate == null || !mounted) return;
      month = DateTime(selectedDate.year, selectedDate.month);
    } else if (selection.period == _FeeExportPeriod.year) {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Choose a date in the calendar year',
      );
      if (selectedDate == null || !mounted) return;
      monthRangeStart = DateTime(selectedDate.year, 1);
      monthRangeEnd = DateTime(selectedDate.year, 12);
    } else if (selection.period == _FeeExportPeriod.session) {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Choose a date in the April–March session',
      );
      if (selectedDate == null || !mounted) return;
      final startYear = selectedDate.month >= DateTime.april
          ? selectedDate.year
          : selectedDate.year - 1;
      monthRangeStart = DateTime(startYear, DateTime.april);
      monthRangeEnd = DateTime(startYear + 1, DateTime.march);
      sessionLabel = '$startYear-${startYear + 1}';
    } else if (selection.period == _FeeExportPeriod.date) {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Choose fee charge date',
      );
      if (selectedDate == null || !mounted) return;
      range = DateTimeRange(start: selectedDate, end: selectedDate);
    } else {
      final selectedDate = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Choose a date in the week',
      );
      if (selectedDate == null || !mounted) return;
      final start = selectedDate.subtract(
        Duration(days: selectedDate.weekday - DateTime.monday),
      );
      range = DateTimeRange(
        start: start,
        end: start.add(const Duration(days: 6)),
      );
    }

    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final charges = monthRangeStart != null
          ? await _repository.getChargesForMonthRange(
              _monthKeyFor(monthRangeStart),
              _monthKeyFor(monthRangeEnd!),
              search: _searchController.text,
              studentIds: widget.allowedStudentIds,
            )
          : month == null
          ? await _repository.getChargesCreatedBetween(
              range!.start,
              range.end,
              search: _searchController.text,
              studentIds: widget.allowedStudentIds,
            )
          : await _repository.getMonthlyCharges(
              '${month.year}-${month.month.toString().padLeft(2, '0')}',
              search: _searchController.text,
              studentIds: widget.allowedStudentIds,
            );
      final exportCharges = charges
          .where((charge) {
            switch (selection.status) {
              case _FeeExportStatus.all:
                return true;
              case _FeeExportStatus.paid:
                return charge.totalOutstanding == 0;
              case _FeeExportStatus.unpaid:
                return charge.status == 'Unpaid';
              case _FeeExportStatus.partialPaid:
                return charge.status == 'Partial';
              case _FeeExportStatus.outstandingDues:
                return charge.totalOutstanding > 0;
            }
          })
          .toList(growable: false);
      final reportTitle = month != null
          ? 'TLC RECEIPT OF MONTH-WISE (${_monthLabel(month)})'
          : selection.period == _FeeExportPeriod.year
          ? 'TLC RECEIPT OF YEAR-WISE (${monthRangeStart!.year})'
          : selection.period == _FeeExportPeriod.session
          ? 'TLC RECEIPT OF SESSION-WISE ($sessionLabel)'
          : selection.period == _FeeExportPeriod.date
          ? 'TLC RECEIPT OF DATE-WISE (${_dateLabel(range!.start)})'
          : 'TLC RECEIPT OF WEEK-WISE '
                '(${_shortDateLabel(range!.start)} to '
                '${_shortDateLabel(range.end)})';
      final periodKey = month != null
          ? '${month.year}${month.month.toString().padLeft(2, '0')}'
          : selection.period == _FeeExportPeriod.year
          ? 'year_${monthRangeStart!.year}'
          : selection.period == _FeeExportPeriod.session
          ? 'session_$sessionLabel'
          : selection.period == _FeeExportPeriod.date
          ? _dateKey(range!.start)
          : '${_dateKey(range!.start)}_to_${_dateKey(range.end)}';
      final statusKey = switch (selection.status) {
        _FeeExportStatus.all => 'all',
        _FeeExportStatus.paid => 'paid',
        _FeeExportStatus.unpaid => 'unpaid',
        _FeeExportStatus.partialPaid => 'partial_paid',
        _FeeExportStatus.outstandingDues => 'outstanding_dues',
      };
      final location = await FilePicker.saveFile(
        dialogTitle: 'Save fees and vouchers Excel file',
        fileName: 'TLC_Fee_Ledger_${periodKey}_$statusKey.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: FeeExcelExporter.encode(
          exportCharges,
          title: reportTitle,
          emptyMessage:
              'No fee records matched the selected period and status.',
        ),
      );
      if (!mounted) return;
      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel file save was canceled.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${exportCharges.length} fee records saved to $location',
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee ledger export failed: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fee ledger export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _collectPayment(FeeCharge charge) async {
    final entry = await showDialog<_PaymentEntry>(
      context: context,
      builder: (context) => _FeePaymentDialog(charge: charge),
    );
    if (entry == null || !mounted) return;

    try {
      final payment = await _repository.recordPayment(
        charge: charge,
        amount: entry.amount,
        applyToFeeId: entry.applyToFeeId,
        paymentMethod: entry.method,
        notes: entry.notes,
        receivedBy: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _loadCharges();
      });
      await showDialog<void>(
        context: context,
        builder: (context) => _ReceiptDialog(
          profile: widget.profile,
          payment: payment,
          onSavePdf: () => _saveReceipt(payment),
          onPrint: () => _printReceipt(payment),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Payment could not be recorded: $error');
      }
    }
  }

  Future<void> _editChargeBreakdown(FeeCharge charge) async {
    final entry = await showDialog<_FeeBreakdownEntry>(
      context: context,
      builder: (context) => _FeeBreakdownDialog(charge: charge),
    );
    if (entry == null || !mounted) return;

    try {
      await _repository.updateChargeBreakdown(
        charge: charge,
        fees: entry.fees,
        annual: entry.annual,
        admission: entry.admission,
        lab: entry.lab,
        copies: entry.copies,
        stationery: entry.stationery,
        extras: entry.extras,
        lpc: entry.lpc,
        remarks: entry.remarks,
        actor: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _loadCharges();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fee voucher updated.')));
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee voucher could not be updated: $error');
      }
    }
  }

  Future<void> _showHistory(FeeCharge charge) async {
    try {
      final payments = await _repository.getPayments(charge.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _PaymentHistoryDialog(
          studentName: charge.studentName,
          payments: payments,
          canReverse: _canReversePayments,
          onReverse: _reversePayment,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Payment history could not be loaded: $error');
      }
    }
  }

  Future<void> _reversePayment(FeePayment payment) async {
    if (!_canReversePayments || payment.isReversal || payment.isReversed) {
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReverseFeePaymentDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      await _repository.reversePayment(
        paymentId: payment.paymentId,
        actor: widget.user,
        reason: reason,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _loadCharges();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Receipt ${payment.receiptNumber} reversed. The original receipt remains in payment history.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee payment could not be reversed: $error');
      }
    }
  }

  Future<void> _saveReceipt(FeePayment payment) async {
    try {
      final bytes = await FeeReceiptPdf.build(
        profile: widget.profile,
        payment: payment,
      );
      final location = await FilePicker.saveFile(
        fileName: '${payment.receiptNumber}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Save fee receipt as PDF',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (!mounted || location == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Receipt saved to $location')));
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'PDF receipt could not be saved: $error');
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    }
  }

  Future<void> _printReceipt(FeePayment payment) async {
    try {
      await Printing.layoutPdf(
        name: '${payment.receiptNumber}.pdf',
        onLayout: (_) =>
            FeeReceiptPdf.build(profile: widget.profile, payment: payment),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee receipt could not be printed: $error');
      }
    }
  }

  Future<void> _printLedger(List<FeeCharge> charges) async {
    if (_printing || charges.isEmpty) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'TLC_Fee_Ledger_$_monthKey.pdf',
        onLayout: (_) => FeeLedgerPdf.build(
          profile: widget.profile,
          monthLabel: _monthLabel(_month),
          charges: charges,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee ledger could not be printed: $error');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _printVouchers(List<FeeCharge> charges) async {
    if (_printing || charges.isEmpty) return;
    setState(() => _printing = true);
    try {
      final bytes = await FeeVoucherPdf.build(
        profile: widget.profile,
        charges: charges,
      );
      if (!mounted) return;
      await Printing.layoutPdf(
        name: 'TLC_Fee_Vouchers_$_monthKey.pdf',
        format: PdfPageFormat.a5.landscape,
        onLayout: (_) async => bytes,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee vouchers could not be printed: $error');
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FeeCharge>>(
    future: _charges,
    builder: (context, snapshot) {
      final charges = snapshot.data ?? const <FeeCharge>[];
      final totalDue = charges.fold<double>(
        0,
        (total, charge) => total + charge.amountDue,
      );
      final totalPaid = charges.fold<double>(
        0,
        (total, charge) => total + charge.amountPaid,
      );
      final totalBalance = charges.fold<double>(
        0,
        (total, charge) => total + charge.totalOutstanding,
      );

      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'FEES & VOUCHERS',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Generate monthly charges, record partial payments, and issue branded receipts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF727B89)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _selectMonth,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(_monthLabel(_month)),
                    ),
                    if (snapshot.hasData)
                      OutlinedButton.icon(
                        onPressed: _exporting ? null : _exportCharges,
                        icon: _exporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                        label: Text(
                          _exporting ? 'Exporting...' : 'Export Excel',
                        ),
                      ),
                    if (snapshot.hasData && charges.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _printing
                            ? null
                            : () => _printLedger(charges),
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print_outlined),
                        label: Text(_printing ? 'Preparing...' : 'Print'),
                      ),
                    if (snapshot.hasData && charges.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _printing
                            ? null
                            : () => _printVouchers(charges),
                        icon: _printing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.receipt_long_outlined),
                        label: Text(
                          _printing
                              ? 'Preparing...'
                              : 'Print vouchers (2 copies)',
                        ),
                      ),
                    if (widget.canManageCharges)
                      FilledButton.icon(
                        onPressed: _generating ? null : _generateCharges,
                        icon: _generating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.playlist_add_rounded, size: 18),
                        label: const Text('Generate monthly charges'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  widget.canManageCharges
                      ? 'Charges use each student’s individual monthly fee. Existing charges are never overwritten. '
                            'Set or update fees in Student records before generating a new month.'
                      : 'Showing fee records only for students linked to your account.',
                  style: const TextStyle(
                    color: Color(0xFF727B89),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Receipts are permanent. Only an Administrator can record a reversal, and the original receipt and correction stay in payment history.',
                  style: TextStyle(
                    color: Color(0xFF727B89),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _MessageBanner(message: _error!, isError: true),
                ],
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900 ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 94,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _SummaryCard(
                          title: 'Total billed',
                          amount: totalDue,
                          icon: Icons.request_quote_outlined,
                          color: widget.primaryColor,
                        ),
                        _SummaryCard(
                          title: 'Collected',
                          amount: totalPaid,
                          icon: Icons.payments_outlined,
                          color: const Color(0xFF38805A),
                        ),
                        _SummaryCard(
                          title: 'Outstanding',
                          amount: totalBalance,
                          icon: Icons.pending_actions_outlined,
                          color: const Color(0xFFAA6A21),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search student name or G.R. number',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE7E9EE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE7E9EE)),
                    ),
                  ),
                  onChanged: (_) => setState(_loadCharges),
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  _MessageBanner(
                    message:
                        'Fee records could not be loaded: ${snapshot.error}',
                    isError: true,
                    onRetry: () => setState(_loadCharges),
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (charges.isEmpty)
                  const _EmptyFees()
                else
                  _ChargesTable(
                    charges: charges,
                    canCollect: widget.canAcceptPayments,
                    canEdit: widget.canManageCharges,
                    onCollect: _collectPayment,
                    onEdit: _editChargeBreakdown,
                    onHistory: _showHistory,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  static String _monthLabel(DateTime month) {
    const names = [
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
    return '${names[month.month - 1]} ${month.year}';
  }

  static String _dateLabel(DateTime date) =>
      '${_shortDateLabel(date)} (${_weekdayName(date.weekday)})';

  static String _shortDateLabel(DateTime date) =>
      '${_ordinal(date.day)} ${_monthAbbreviation(date.month)}, '
      '${(date.year % 100).toString().padLeft(2, '0')}';

  static String _ordinal(int day) {
    final suffix = day % 100 >= 11 && day % 100 <= 13
        ? 'th'
        : switch (day % 10) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
    return '$day$suffix';
  }

  static String _monthAbbreviation(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];

  static String _weekdayName(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];

  static String _dateKey(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  static String _monthKeyFor(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

class _FeeBreakdownEntry {
  final double fees;
  final double annual;
  final double admission;
  final double lab;
  final double copies;
  final double stationery;
  final double extras;
  final double lpc;
  final String remarks;

  const _FeeBreakdownEntry({
    required this.fees,
    required this.annual,
    required this.admission,
    required this.lab,
    required this.copies,
    required this.stationery,
    required this.extras,
    required this.lpc,
    required this.remarks,
  });
}

class _FeeBreakdownDialog extends StatefulWidget {
  final FeeCharge charge;

  const _FeeBreakdownDialog({required this.charge});

  @override
  State<_FeeBreakdownDialog> createState() => _FeeBreakdownDialogState();
}

class _FeeBreakdownDialogState extends State<_FeeBreakdownDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _amountControllers;
  late final TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    final charge = widget.charge;
    _amountControllers = {
      'Fees': TextEditingController(text: charge.fees.toStringAsFixed(2)),
      'Annual': TextEditingController(text: charge.annual.toStringAsFixed(2)),
      'Admission': TextEditingController(
        text: charge.admission.toStringAsFixed(2),
      ),
      'Lab': TextEditingController(text: charge.lab.toStringAsFixed(2)),
      'Copies': TextEditingController(text: charge.copies.toStringAsFixed(2)),
      'Stationery': TextEditingController(
        text: charge.stationery.toStringAsFixed(2),
      ),
      'Extras': TextEditingController(text: charge.extras.toStringAsFixed(2)),
      'LPC': TextEditingController(text: charge.lpc.toStringAsFixed(2)),
    };
    _remarksController = TextEditingController(text: charge.remarks);
  }

  @override
  void dispose() {
    for (final controller in _amountControllers.values) {
      controller.dispose();
    }
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit fee heads'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter Annual or Admission only when due. Apply LPC under school policy.',
              ),
              const SizedBox(height: 12),
              for (final entry in _amountControllers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: entry.value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: entry.key,
                      prefixText: 'PKR ',
                    ),
                    validator: (value) {
                      final amount = double.tryParse(value?.trim() ?? '');
                      if (amount == null || !amount.isFinite || amount < 0) {
                        return 'Enter a non-negative amount.';
                      }
                      return null;
                    },
                  ),
                ),
              TextFormField(
                controller: _remarksController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Remarks'),
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
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final amounts = _amountControllers.map(
            (key, controller) =>
                MapEntry(key, double.parse(controller.text.trim())),
          );
          Navigator.of(context).pop(
            _FeeBreakdownEntry(
              fees: amounts['Fees']!,
              annual: amounts['Annual']!,
              admission: amounts['Admission']!,
              lab: amounts['Lab']!,
              copies: amounts['Copies']!,
              stationery: amounts['Stationery']!,
              extras: amounts['Extras']!,
              lpc: amounts['LPC']!,
              remarks: _remarksController.text,
            ),
          );
        },
        child: const Text('Save voucher'),
      ),
    ],
  );
}

class _PaymentEntry {
  final double amount;
  final String? applyToFeeId;
  final String method;
  final String notes;

  const _PaymentEntry(this.amount, this.applyToFeeId, this.method, this.notes);
}

class _FeePaymentDialog extends StatefulWidget {
  final FeeCharge charge;

  const _FeePaymentDialog({required this.charge});

  @override
  State<_FeePaymentDialog> createState() => _FeePaymentDialogState();
}

class _FeePaymentDialogState extends State<_FeePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _notesController = TextEditingController();
  String _method = 'Cash';
  bool _isPartial = false;
  String? _applyToFeeId;

  List<FeeCharge> get _payableCharges => [
    ...widget.charge.arrears,
    widget.charge,
  ].where((charge) => charge.balance > 0).toList(growable: false);

  String _chargeBreakdown(FeeCharge charge) => [
    if (charge.fees > 0) 'Fees ${charge.fees.toStringAsFixed(2)}',
    if (charge.annual > 0) 'Annual ${charge.annual.toStringAsFixed(2)}',
    if (charge.admission > 0)
      'Admission ${charge.admission.toStringAsFixed(2)}',
    if (charge.lab > 0) 'Lab ${charge.lab.toStringAsFixed(2)}',
    if (charge.copies > 0) 'Copies ${charge.copies.toStringAsFixed(2)}',
    if (charge.stationery > 0)
      'Stationery ${charge.stationery.toStringAsFixed(2)}',
    if (charge.extras > 0) 'Extras ${charge.extras.toStringAsFixed(2)}',
    if (charge.lpc > 0) 'LPC ${charge.lpc.toStringAsFixed(2)}',
  ].join(' · ');

  FeeCharge? get _selectedCharge => _applyToFeeId == null
      ? null
      : _payableCharges.firstWhere((charge) => charge.id == _applyToFeeId);

  double get _paymentLimit =>
      _selectedCharge?.balance ?? widget.charge.totalOutstanding;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.charge.totalOutstanding.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _PaymentEntry(
        _isPartial
            ? double.parse(_amountController.text.trim())
            : _paymentLimit,
        _applyToFeeId,
        _method,
        _notesController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record fee payment'),
    content: SizedBox(
      width: 430,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.charge.studentName}  •  G.R. ${widget.charge.admissionNumber}\n'
                '${widget.charge.className}  •  ${widget.charge.monthKey}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF687080),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _applyToFeeId,
              decoration: const InputDecoration(labelText: 'Apply payment to'),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'Oldest outstanding month first · PKR '
                    '${widget.charge.totalOutstanding.toStringAsFixed(2)}',
                  ),
                ),
                for (final fee in _payableCharges)
                  DropdownMenuItem<String?>(
                    value: fee.id,
                    child: Text(
                      '${fee.monthKey} · PKR ${fee.balance.toStringAsFixed(2)}'
                      '${_chargeBreakdown(fee).isEmpty ? '' : ' · ${_chargeBreakdown(fee)}'}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _applyToFeeId = value;
                _amountController.text = _paymentLimit.toStringAsFixed(2);
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Full'),
                  selected: !_isPartial,
                  onSelected: (selected) {
                    if (selected) setState(() => _isPartial = false);
                  },
                ),
                ChoiceChip(
                  label: const Text('Partial'),
                  selected: _isPartial,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _isPartial = true;
                        _amountController.text = _paymentLimit.toStringAsFixed(
                          2,
                        );
                      });
                    }
                  },
                ),
              ],
            ),
            if (_isPartial)
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Partial amount received (PKR)',
                  helperText:
                      'Maximum for this selection: PKR '
                      '${_paymentLimit.toStringAsFixed(2)}',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Enter an amount greater than zero.';
                  }
                  if (amount > _paymentLimit) {
                    return 'Amount cannot exceed the selected balance.';
                  }
                  return null;
                },
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Full payment: PKR ${_paymentLimit.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                DropdownMenuItem(
                  value: 'Bank transfer',
                  child: Text('Bank transfer'),
                ),
                DropdownMenuItem(
                  value: 'Mobile wallet',
                  child: Text('Mobile wallet'),
                ),
                DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save payment')),
    ],
  );
}

class _ReceiptDialog extends StatelessWidget {
  final SchoolProfile profile;
  final FeePayment payment;
  final Future<void> Function() onSavePdf;
  final Future<void> Function() onPrint;

  const _ReceiptDialog({
    required this.profile,
    required this.payment,
    required this.onSavePdf,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Payment recorded'),
    content: SizedBox(
      width: 470,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${profile.schoolName}\nFee receipt ${payment.receiptNumber}',
            style: TextStyle(
              color: profile.primaryColor,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _receiptLine('Student', payment.studentName),
          _receiptLine('G.R. number', payment.admissionNumber),
          _receiptLine(
            'Class / month',
            '${payment.className} / ${payment.monthKey}',
          ),
          _receiptLine(
            'Received',
            'PKR ${payment.amountPaidThisReceipt.toStringAsFixed(2)}',
          ),
          _receiptLine(
            'Outstanding before',
            'PKR ${payment.amountDue.toStringAsFixed(2)}',
          ),
          for (final allocation in payment.allocations)
            _receiptLine(
              'Applied to ${allocation.monthKey}',
              'PKR ${allocation.amount.toStringAsFixed(2)}',
            ),
          _receiptLine(
            'Outstanding after',
            'PKR ${payment.balance.toStringAsFixed(2)}',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      OutlinedButton.icon(
        onPressed: onPrint,
        icon: const Icon(Icons.print_outlined),
        label: const Text('Print receipt'),
      ),
      FilledButton.icon(
        onPressed: onSavePdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Save PDF'),
      ),
    ],
  );

  static Widget _receiptLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF687080), fontSize: 12),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

class _PaymentHistoryDialog extends StatelessWidget {
  final String studentName;
  final List<FeePayment> payments;
  final bool canReverse;
  final ValueChanged<FeePayment> onReverse;

  const _PaymentHistoryDialog({
    required this.studentName,
    required this.payments,
    required this.canReverse,
    required this.onReverse,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Payment history • $studentName'),
    content: SizedBox(
      width: 560,
      child: payments.isEmpty
          ? const Text('No payments have been recorded for this month.')
          : ListView.separated(
              shrinkWrap: true,
              itemCount: payments.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final payment = payments[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    payment.isReversal
                        ? 'Reversal: PKR ${payment.amountPaidThisReceipt.abs().toStringAsFixed(2)}'
                        : 'PKR ${payment.amountPaidThisReceipt.toStringAsFixed(2)} applied',
                  ),
                  subtitle: Text(
                    payment.isReversal
                        ? '${payment.receiptNumber} • By ${payment.reversedByName} • ${payment.reversalReason}'
                        : '${payment.receiptNumber} • ${payment.paymentMethod}'
                              '${payment.receiptAmount > payment.amountPaidThisReceipt ? ' • Receipt total PKR ${payment.receiptAmount.toStringAsFixed(2)}' : ''}'
                              '${payment.receivedByName.isEmpty ? '' : ' • Received by ${payment.receivedByName} (${payment.receivedByRole})'}'
                              '${payment.isReversed ? ' • Reversed' : ''}',
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_dateLabel(payment.paidAt)),
                      if (canReverse &&
                          !payment.isReversal &&
                          !payment.isReversed)
                        TextButton(
                          onPressed: () => onReverse(payment),
                          child: const Text('Reverse'),
                        ),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );

  static String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _ReverseFeePaymentDialog extends StatefulWidget {
  const _ReverseFeePaymentDialog();

  @override
  State<_ReverseFeePaymentDialog> createState() =>
      _ReverseFeePaymentDialogState();
}

class _ReverseFeePaymentDialogState extends State<_ReverseFeePaymentDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reverse fee receipt?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Only Administrators can do this. This does not delete the original receipt; both the receipt and this correction are kept permanently.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _reasonController,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Reason for correction',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final reason = _reasonController.text.trim();
          if (reason.isEmpty) {
            setState(() => _error = 'Enter a reason to continue.');
            return;
          }
          Navigator.of(context).pop(reason);
        },
        child: const Text('Confirm reversal'),
      ),
    ],
  );
}

class _ChargesTable extends StatelessWidget {
  final List<FeeCharge> charges;
  final bool canCollect;
  final bool canEdit;
  final ValueChanged<FeeCharge> onCollect;
  final ValueChanged<FeeCharge> onEdit;
  final ValueChanged<FeeCharge> onHistory;

  const _ChargesTable({
    required this.charges,
    required this.canCollect,
    required this.canEdit,
    required this.onCollect,
    required this.onEdit,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE7E9EE)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        border: TableBorder.all(color: const Color(0xFFD7DCE3), width: 0.7),
        headingTextStyle: const TextStyle(
          color: Color(0xFF687080),
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        columns: const [
          DataColumn(label: Center(child: Text('STUDENT'))),
          DataColumn(label: Center(child: Text('G.R. / CLASS'))),
          DataColumn(label: Center(child: Text('DUE'))),
          DataColumn(label: Center(child: Text('PAID'))),
          DataColumn(label: Center(child: Text('ARREARS'))),
          DataColumn(label: Center(child: Text('BALANCE'))),
          DataColumn(label: Center(child: Text('STATUS'))),
          DataColumn(label: Center(child: Text('ACTIONS'))),
        ],
        rows: [
          for (final charge in charges)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 180,
                    child: Text(
                      charge.studentName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                DataCell(
                  Text('${charge.admissionNumber} / ${charge.className}'),
                ),
                DataCell(Text(_money(charge.amountDue))),
                DataCell(Text(_money(charge.amountPaid))),
                DataCell(Text(_money(charge.arrearsBalance))),
                DataCell(
                  Text(
                    _money(charge.totalOutstanding),
                    style: TextStyle(
                      color: charge.totalOutstanding > 0
                          ? const Color(0xFFAA6A21)
                          : const Color(0xFF38805A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DataCell(_StatusChip(status: charge.status)),
                DataCell(
                  Row(
                    children: [
                      if (canEdit)
                        IconButton(
                          tooltip: 'Edit fee heads',
                          onPressed: () => onEdit(charge),
                          icon: const Icon(Icons.edit_outlined, size: 19),
                        ),
                      if (canCollect && charge.totalOutstanding > 0)
                        TextButton(
                          onPressed: () => onCollect(charge),
                          child: const Text('Collect'),
                        ),
                      IconButton(
                        tooltip: 'Payment history',
                        onPressed: () => onHistory(charge),
                        icon: const Icon(Icons.history_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  static String _money(double amount) => 'PKR ${amount.toStringAsFixed(2)}';
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.amount,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF687080), fontSize: 11),
              ),
              const SizedBox(height: 5),
              Text(
                'PKR ${amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF252B36),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Paid' => const Color(0xFF38805A),
      'Partial' => const Color(0xFFAA6A21),
      _ => const Color(0xFF8E1717),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyFees extends StatelessWidget {
  const _EmptyFees();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: const Column(
      children: [
        Icon(Icons.receipt_long_outlined, color: Color(0xFFC62828), size: 32),
        SizedBox(height: 10),
        Text(
          'No fee charges for this month yet.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          'Set each student’s monthly fee in Student records, then generate this month’s charges.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF727B89), fontSize: 12),
        ),
      ],
    ),
  );
}

class _MessageBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  const _MessageBanner({
    required this.message,
    required this.isError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFF9A2222) : const Color(0xFF345B36);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFF0F0) : const Color(0xFFF4F8F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError ? const Color(0xFFF1CBCB) : const Color(0xFFD9E9D9),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 12)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

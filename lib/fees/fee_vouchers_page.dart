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

  Future<void> _exportCharges(List<FeeCharge> charges) async {
    if (_exporting || charges.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final location = await FilePicker.saveFile(
        dialogTitle: 'Export fee ledger',
        fileName: 'TLC_Fee_Ledger_$_monthKey.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: FeeExcelExporter.encode(charges),
      );
      if (!mounted || location == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${charges.length} fee records exported to $location'),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Fee ledger export failed: $error');
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
        (total, charge) => total + charge.balance,
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF727B89),
                  ),
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
                    if (snapshot.hasData && charges.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _exporting
                            ? null
                            : () => _exportCharges(charges),
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
                            : const Icon(
                                Icons.playlist_add_rounded,
                                size: 18,
                              ),
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
                    onCollect: _collectPayment,
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
}

class _PaymentEntry {
  final double amount;
  final String method;
  final String notes;

  const _PaymentEntry(this.amount, this.method, this.notes);
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

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.charge.balance.toStringAsFixed(2),
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
        double.parse(_amountController.text.trim()),
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
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount received (PKR)',
                helperText:
                    'Remaining balance: PKR ${widget.charge.balance.toStringAsFixed(2)}',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final amount = double.tryParse(value?.trim() ?? '');
                if (amount == null || amount <= 0) {
                  return 'Enter an amount greater than zero.';
                }
                if (amount > widget.charge.balance) {
                  return 'Amount cannot exceed the remaining balance.';
                }
                return null;
              },
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
          _receiptLine('Balance', 'PKR ${payment.balance.toStringAsFixed(2)}'),
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
                        : 'PKR ${payment.amountPaidThisReceipt.toStringAsFixed(2)}',
                  ),
                  subtitle: Text(
                    payment.isReversal
                        ? '${payment.receiptNumber} • By ${payment.reversedByName} • ${payment.reversalReason}'
                        : '${payment.receiptNumber} • ${payment.paymentMethod}'
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
  final ValueChanged<FeeCharge> onCollect;
  final ValueChanged<FeeCharge> onHistory;

  const _ChargesTable({
    required this.charges,
    required this.canCollect,
    required this.onCollect,
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
        border: TableBorder.all(
          color: const Color(0xFFD7DCE3),
          width: 0.7,
        ),
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
                DataCell(
                  Text(
                    _money(charge.balance),
                    style: TextStyle(
                      color: charge.balance > 0
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
                      if (canCollect && charge.balance > 0)
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

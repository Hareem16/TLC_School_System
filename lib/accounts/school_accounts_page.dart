import 'package:flutter/material.dart';

import '../auth/app_user.dart';
import '../data/school_finance_repository.dart';

class SchoolAccountsPage extends StatefulWidget {
  final AppUser user;

  const SchoolAccountsPage({super.key, required this.user});

  @override
  State<SchoolAccountsPage> createState() => _SchoolAccountsPageState();
}

class _SchoolAccountsPageState extends State<SchoolAccountsPage> {
  final SchoolFinanceRepository _repository = SchoolFinanceRepository();
  SchoolAccountSummary? _summary;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _repository.getAccountSummary();
      if (mounted) {
        setState(() {
          _summary = summary;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'School accounts could not be loaded: $error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editOpeningBalance() async {
    final summary = _summary;
    if (summary == null || _working) return;
    final amount = TextEditingController(
      text: summary.openingBalance.toStringAsFixed(2),
    );
    var date = summary.openingBalanceDate;
    String? validationError;
    final entry = await showDialog<_OpeningBalanceEntry>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Opening school-account balance'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Opening balance (PKR)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      helpText: 'Opening balance is at the start of this date',
                    );
                    if (selected != null) {
                      setDialogState(() => date = selected);
                    }
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Effective date: ${_dateLabel(date)}'),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'This amount is the balance at the start of the selected date. Fee receipts and recorded salary payments from that date onward will change the balance.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.trim());
                if (value == null ||
                    !value.isFinite ||
                    value < 0 ||
                    (value * 100 - (value * 100).round()).abs() >= 0.000001) {
                  setDialogState(
                    () => validationError =
                        'Enter a non-negative amount with up to two decimals.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _OpeningBalanceEntry(amount: value, date: date),
                );
              },
              child: const Text('Save opening balance'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (entry == null || !mounted) return;

    setState(() => _working = true);
    try {
      await _repository.setOpeningBalance(
        amount: entry.amount,
        date: entry.date,
        actor: widget.user,
      );
      await _load();
    } catch (error) {
      _toast('Opening balance could not be saved: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _money(double value) => 'PKR ${value.toStringAsFixed(2)}';

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _monthLabel(String key) {
    final date = DateTime.parse('$key-01');
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
    return '${months[date.month - 1]} ${date.year}';
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F9FB),
    appBar: AppBar(
      title: const Text('School Accounts'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Refresh account report',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          )
        : _buildReport(_summary!),
  );

  Widget _buildReport(SchoolAccountSummary summary) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded school-account balance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _money(summary.currentBalance),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Opening: ${_money(summary.openingBalance)} from ${_dateLabel(summary.openingBalanceDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _working ? null : _editOpeningBalance,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Set opening balance'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Monthly cashbook: fee receipts minus fee reversals and recorded teacher salary payments. Salary entries are records only; they do not transfer money or include other school expenses.',
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (summary.months.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('No account months are available for this period.'),
          ),
        )
      else
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Month')),
                DataColumn(label: Text('Fee receipts')),
                DataColumn(label: Text('Reversals')),
                DataColumn(label: Text('Teacher salaries')),
                DataColumn(label: Text('Net movement')),
                DataColumn(label: Text('Closing balance')),
              ],
              rows: summary.months
                  .map(
                    (month) => DataRow(
                      cells: [
                        DataCell(Text(_monthLabel(month.monthKey))),
                        DataCell(Text(_money(month.feeReceipts))),
                        DataCell(Text(_money(month.feeReversals))),
                        DataCell(Text(_money(month.salaryPayments))),
                        DataCell(Text(_money(month.netMovement))),
                        DataCell(Text(_money(month.closingBalance))),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
    ],
  );
}

class _OpeningBalanceEntry {
  final double amount;
  final DateTime date;

  const _OpeningBalanceEntry({required this.amount, required this.date});
}

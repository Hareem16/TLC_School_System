import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../data/inventory_excel_exporter.dart';
import '../data/inventory_excel_importer.dart';
import '../data/inventory_report_pdf.dart';
import '../data/inventory_repository.dart';
import '../school_profile.dart';

class InventoryPage extends StatefulWidget {
  final Color primaryColor;
  final SchoolProfile? profile;

  const InventoryPage({super.key, required this.primaryColor, this.profile});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final InventoryRepository _repository = InventoryRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<InventoryItem>> _items;
  bool _importing = false;
  bool _exporting = false;
  bool _printing = false;
  bool _downloadingTemplate = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = _repository.getItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _items = _repository.getItems(search: _searchController.text);
  }

  Future<void> _saveItem({InventoryItem? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final category = TextEditingController(text: existing?.category ?? '');
    final unit = TextEditingController(text: existing?.unit ?? 'piece');
    final reorder = TextEditingController(
      text: existing?.reorderLevel.toString() ?? '0',
    );
    final notes = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();
    try {
      final input = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(existing == null ? 'Add inventory item' : 'Edit item'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _formField(name, 'Item name', required: true),
                    _formField(category, 'Category', required: true),
                    _formField(
                      unit,
                      'Unit (e.g. piece, box, ream)',
                      required: true,
                    ),
                    _formField(
                      reorder,
                      'Low-stock alert level',
                      number: true,
                      validator: (value) {
                        final number = double.tryParse(value?.trim() ?? '');
                        return number == null || number < 0
                            ? 'Enter a non-negative number.'
                            : null;
                      },
                    ),
                    _formField(notes, 'Notes', maxLines: 3),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save item'),
            ),
          ],
        ),
      );
      if (input != true || !mounted) return;
      await _repository.saveItem(
        id: existing?.id,
        name: name.text,
        category: category.text,
        unit: unit.text,
        reorderLevel: double.parse(reorder.text.trim()),
        notes: notes.text,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _reload();
      });
      _message(
        existing == null ? 'Inventory item added.' : 'Inventory item updated.',
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Inventory item could not be saved: $error');
      }
    } finally {
      name.dispose();
      category.dispose();
      unit.dispose();
      reorder.dispose();
      notes.dispose();
    }
  }

  Future<void> _recordMovement(
    InventoryItem item, {
    required String direction,
  }) async {
    final quantity = TextEditingController();
    final unitCost = TextEditingController(text: '0');
    final supplier = TextEditingController();
    final reference = TextEditingController();
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final input = await showDialog<_MovementInput>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              direction == 'in'
                  ? 'Receive stock: ${item.name}'
                  : 'Issue stock: ${item.name}',
            ),
            content: SizedBox(
              width: 460,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _formField(
                        quantity,
                        'Quantity (${item.unit})',
                        number: true,
                        validator: (value) {
                          final amount = double.tryParse(value?.trim() ?? '');
                          return amount == null || amount <= 0
                              ? 'Enter a quantity greater than zero.'
                              : null;
                        },
                      ),
                      if (direction == 'in') ...[
                        _formField(
                          unitCost,
                          'Unit cost (PKR)',
                          number: true,
                          validator: (value) {
                            final amount = double.tryParse(value?.trim() ?? '');
                            return amount == null || amount < 0
                                ? 'Enter a non-negative cost.'
                                : null;
                          },
                        ),
                        _formField(supplier, 'Supplier'),
                      ],
                      _formField(reference, 'Reference / invoice number'),
                      _formField(notes, 'Notes', maxLines: 2),
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
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    dialogContext,
                    _MovementInput(
                      quantity: double.parse(quantity.text.trim()),
                      unitCost: double.tryParse(unitCost.text.trim()) ?? 0,
                      supplier: supplier.text,
                      reference: reference.text,
                      notes: notes.text,
                    ),
                  );
                },
                child: Text(direction == 'in' ? 'Receive' : 'Issue'),
              ),
            ],
          );
        },
      );
      if (input == null || !mounted) return;
      await _repository.recordMovement(
        item: item,
        direction: direction,
        quantity: input.quantity,
        unitCost: input.unitCost,
        supplier: input.supplier,
        reference: input.reference,
        notes: input.notes,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _reload();
      });
      _message(direction == 'in' ? 'Stock received.' : 'Stock issued.');
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Stock movement failed: $error');
    } finally {
      quantity.dispose();
      unitCost.dispose();
      supplier.dispose();
      reference.dispose();
      notes.dispose();
    }
  }

  Future<void> _showHistory(InventoryItem item) async {
    try {
      final movements = await _repository.getMovements(item.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Stock history • ${item.name}'),
          content: SizedBox(
            width: 680,
            child: movements.isEmpty
                ? const Text('No stock movements have been recorded.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: movements.length,
                    itemBuilder: (context, index) {
                      final movement = movements[index];
                      final isIncoming = movement.direction == 'in';
                      return ListTile(
                        leading: Icon(
                          isIncoming
                              ? Icons.call_received_rounded
                              : Icons.call_made_rounded,
                          color: isIncoming
                              ? const Color(0xFF38805A)
                              : const Color(0xFFC62828),
                        ),
                        title: Text(
                          '${isIncoming ? 'Received' : 'Issued'} '
                          '${movement.quantity.toStringAsFixed(2)} ${item.unit}',
                        ),
                        subtitle: Text(
                          [
                            _dateLabel(movement.movedAt),
                            if (movement.reference.isNotEmpty)
                              'Ref: ${movement.reference}',
                            if (movement.supplier.isNotEmpty)
                              'Supplier: ${movement.supplier}',
                          ].join(' • '),
                        ),
                        trailing: isIncoming
                            ? Text(
                                'PKR ${movement.unitCost.toStringAsFixed(2)}',
                              )
                            : null,
                      );
                    },
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
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Stock history could not be loaded: $error');
      }
    }
  }

  Future<void> _importExcel() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Select inventory workbook',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (files.isEmpty) return;
      final result = InventoryExcelImporter().parse(
        await files.first.readAsBytes(),
      );
      if (result.errors.isNotEmpty) {
        if (!mounted) return;
        await _showImportErrors(result.errors);
        return;
      }

      if (result.items.isEmpty) {
        throw const FormatException('No inventory rows were found to import.');
      }
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import inventory items?'),
          content: Text(
            '${result.items.length} item rows are ready. Matching items will update non-blank unit, reorder level, and notes values; blank cells preserve saved values. '
            'Opening quantities are recorded only for new items so existing stock movement history is not overwritten. '
            '${result.skippedBlankRows} blank rows will be ignored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final counts = await _repository.importItems(result.items);
      if (!mounted) return;
      setState(() {
        _error = null;
        _reload();
      });
      _message(
        'Import complete: ${counts.imported} added, '
        '${counts.updated} updated, ${counts.unchanged} unchanged.',
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Inventory import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _downloadImportTemplate() async {
    if (_downloadingTemplate) return;
    setState(() => _downloadingTemplate = true);
    try {
      final location = await FilePicker.saveFile(
        dialogTitle: 'Save inventory import template',
        fileName: 'TLC_Inventory_Import_Template.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: InventoryExcelExporter.encodeImportTemplate(),
      );
      if (!mounted || location == null) return;
      _message('Inventory template saved to $location');
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Inventory template could not be saved: $error');
      }
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _showImportErrors(List<String> errors) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Workbook needs corrections'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'No records were imported. Correct these rows and try again:',
            ),
            const SizedBox(height: 12),
            for (final error in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(error),
              ),
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

  Future<void> _exportExcel(List<InventoryItem> items) async {
    if (_exporting || items.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final location = await FilePicker.saveFile(
        dialogTitle: 'Export inventory list',
        fileName: 'TLC_Inventory.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: InventoryExcelExporter.encode(items),
      );
      if (!mounted || location == null) return;
      _message('${items.length} inventory items exported to $location');
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Inventory export failed: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printReport(List<InventoryItem> items) async {
    if (_printing || items.isEmpty) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'TLC_Inventory_Report.pdf',
        onLayout: (_) => InventoryReportPdf.build(
          profile: widget.profile ?? SchoolProfile.tlc(),
          items: items,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Inventory report could not be printed: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<InventoryItem>>(
    future: _items,
    builder: (context, snapshot) {
      final items = snapshot.data ?? const <InventoryItem>[];
      final lowStock = items.where((item) => item.isLowStock).length;
      final totalUnits = items.fold<double>(
        0,
        (total, item) => total + item.quantityOnHand,
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'INVENTORY & SUPPLIES',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Track school supplies, stock movements, and low-stock alerts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF727B89), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _downloadingTemplate
                              ? null
                              : _downloadImportTemplate,
                          icon: _downloadingTemplate
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_download_outlined),
                          label: const Text('Excel template'),
                        ),
                        OutlinedButton.icon(
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
                        ),
                        if (snapshot.hasData && items.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _exportExcel(items),
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
                        if (snapshot.hasData && items.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _printing
                                ? null
                                : () => _printReport(items),
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
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.primaryColor,
                          ),
                          onPressed: () => _saveItem(),
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text('Add item'),
                        ),
                      ],
                    ),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  _InventoryBanner(message: _error!, isError: true),
                  const SizedBox(height: 12),
                ],
                if (snapshot.hasError)
                  _InventoryBanner(
                    message:
                        'Inventory records could not be loaded: ${snapshot.error}',
                    isError: true,
                    onRetry: () => setState(_reload),
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 760 ? 3 : 1;
                      return GridView.count(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 92,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _InventorySummary(
                            title: 'Tracked items',
                            value: '${items.length}',
                            icon: Icons.inventory_2_outlined,
                            color: widget.primaryColor,
                          ),
                          _InventorySummary(
                            title: 'Low-stock items',
                            value: '$lowStock',
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFAA6A21),
                          ),
                          _InventorySummary(
                            title: 'Total stock quantity',
                            value: totalUnits.toStringAsFixed(2),
                            icon: Icons.stacked_bar_chart_rounded,
                            color: const Color(0xFF38805A),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search item or category',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(_reload),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const _InventoryEmpty()
                  else
                    _InventoryTable(
                      items: items,
                      onEdit: (item) => _saveItem(existing: item),
                      onReceive: (item) =>
                          _recordMovement(item, direction: 'in'),
                      onIssue: (item) =>
                          _recordMovement(item, direction: 'out'),
                      onHistory: _showHistory,
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _formField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool number = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
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

class _MovementInput {
  final double quantity;
  final double unitCost;
  final String supplier;
  final String reference;
  final String notes;

  const _MovementInput({
    required this.quantity,
    required this.unitCost,
    required this.supplier,
    required this.reference,
    required this.notes,
  });
}

class _InventoryTable extends StatelessWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onEdit;
  final ValueChanged<InventoryItem> onReceive;
  final ValueChanged<InventoryItem> onIssue;
  final ValueChanged<InventoryItem> onHistory;

  const _InventoryTable({
    required this.items,
    required this.onEdit,
    required this.onReceive,
    required this.onIssue,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
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
          DataColumn(label: Center(child: Text('Item'))),
          DataColumn(label: Center(child: Text('Category'))),
          DataColumn(label: Center(child: Text('On hand')), numeric: true),
          DataColumn(
            label: Center(child: Text('Reorder level')),
            numeric: true,
          ),
          DataColumn(label: Center(child: Text('Status'))),
          DataColumn(label: Center(child: Text('Actions'))),
        ],
        rows: [
          for (final item in items)
            DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        item.unit,
                        style: const TextStyle(
                          color: Color(0xFF828A98),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(Text(item.category)),
                DataCell(
                  Text(
                    '${item.quantityOnHand.toStringAsFixed(2)} ${item.unit}',
                  ),
                ),
                DataCell(Text(item.reorderLevel.toStringAsFixed(2))),
                DataCell(_StockStatus(low: item.isLowStock)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Receive stock',
                        onPressed: () => onReceive(item),
                        icon: const Icon(Icons.add_circle_outline),
                        color: const Color(0xFF38805A),
                      ),
                      IconButton(
                        tooltip: 'Issue stock',
                        onPressed: () => onIssue(item),
                        icon: const Icon(Icons.remove_circle_outline),
                        color: const Color(0xFFC62828),
                      ),
                      IconButton(
                        tooltip: 'Movement history',
                        onPressed: () => onHistory(item),
                        icon: const Icon(Icons.history_rounded),
                      ),
                      IconButton(
                        tooltip: 'Edit item',
                        onPressed: () => onEdit(item),
                        icon: const Icon(Icons.edit_outlined),
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
}

class _StockStatus extends StatelessWidget {
  final bool low;

  const _StockStatus({required this.low});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: low ? const Color(0xFFFFF2E2) : const Color(0xFFEAF5EE),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      low ? 'Low stock' : 'In stock',
      style: TextStyle(
        color: low ? const Color(0xFFAA6A21) : const Color(0xFF38805A),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _InventorySummary extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _InventorySummary({
    required this.title,
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
        Icon(icon, color: color, size: 23),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Color(0xFF687080)),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF252B36),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _InventoryEmpty extends StatelessWidget {
  const _InventoryEmpty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(
      child: Text(
        'No inventory items found. Add an item or import a workbook to begin.',
        style: TextStyle(color: Color(0xFF687080)),
      ),
    ),
  );
}

class _InventoryBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  const _InventoryBanner({
    required this.message,
    required this.isError,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFFEEEE) : const Color(0xFFEAF5EE),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: isError
                  ? const Color(0xFF9F2424)
                  : const Color(0xFF34714E),
              fontSize: 12,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

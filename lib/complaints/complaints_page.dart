import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth/app_user.dart';
import '../data/complaint_repository.dart';

class ComplaintsPage extends StatefulWidget {
  final AppUser currentUser;
  final Color primaryColor;
  final bool canManageRecords;

  const ComplaintsPage({
    super.key,
    required this.currentUser,
    required this.primaryColor,
    required this.canManageRecords,
  });

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  final ComplaintRepository _repository = ComplaintRepository();
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'All statuses';
  late Future<List<ComplaintRecord>> _complaints;
  String? _error;

  static const _statuses = ['Open', 'In Progress', 'Resolved', 'Closed'];
  static const _categories = [
    'Academic',
    'Fees',
    'Facilities',
    'Staff',
    'Safety',
    'Other',
  ];
  static const _priorities = ['Low', 'Medium', 'High'];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _complaints = _repository.getAll(
      currentUser: widget.currentUser,
      search: _searchController.text,
      status: _statusFilter,
    );
  }

  Future<void> _addComplaint() async {
    final entry = await showDialog<_ComplaintEntry>(
      context: context,
      builder: (context) => _ComplaintFormDialog(
        reporterName: widget.currentUser.fullName,
        reporterRole: widget.currentUser.role,
        categories: _categories,
        priorities: _priorities,
      ),
    );
    if (entry == null || !mounted) return;
    try {
      await _repository.create(
        currentUser: widget.currentUser,
        contact: entry.contact,
        category: entry.category,
        subject: entry.subject,
        description: entry.description,
        priority: entry.priority,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _reload();
      });
      _message('Complaint submitted.');
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Complaint could not be saved: $error');
      }
    }
  }

  Future<void> _updateComplaint(ComplaintRecord complaint) async {
    if (!widget.canManageRecords) return;
    final update = await showDialog<_ComplaintUpdate>(
      context: context,
      builder: (context) => _ComplaintStatusDialog(complaint: complaint),
    );
    if (update == null || !mounted) return;
    try {
      await _repository.updateStatus(
        currentUser: widget.currentUser,
        complaintId: complaint.id,
        status: update.status,
        resolutionNotes: update.notes,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _reload();
      });
      _message('Complaint status updated.');
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Complaint update failed: $error');
    }
  }

  Future<void> _importTransfer({required bool response}) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final contents = utf8.decode(await file.readAsBytes());
      if (response) {
        await _repository.importResponseJson(
          currentUser: widget.currentUser,
          contents: contents,
        );
      } else {
        await _repository.importSubmissionJson(
          currentUser: widget.currentUser,
          contents: contents,
        );
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _reload();
      });
      _message(
        response ? 'Complaint response imported.' : 'Complaint imported.',
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'File could not be imported: $error');
      }
    }
  }

  Future<void> _exportTransfer(
    ComplaintRecord complaint, {
    required bool response,
  }) async {
    try {
      final contents = response
          ? await _repository.exportResponseJson(
              currentUser: widget.currentUser,
              complaintId: complaint.id,
            )
          : await _repository.exportSubmissionJson(
              currentUser: widget.currentUser,
              complaintId: complaint.id,
            );
      final fileName = response
          ? 'TLC-complaint-response-${complaint.id}.json'
          : 'TLC-complaint-${complaint.id}.json';
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
        dialogTitle: response ? 'Save response file' : 'Save complaint file',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'File could not be saved: $error');
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ComplaintRecord>>(
    future: _complaints,
    builder: (context, snapshot) {
      final complaints = snapshot.data ?? const <ComplaintRecord>[];
      final openCount = complaints
          .where((item) => item.status == 'Open')
          .length;
      final inProgressCount = complaints
          .where((item) => item.status == 'In Progress')
          .length;
      final resolvedCount = complaints
          .where((item) => item.status == 'Resolved' || item.status == 'Closed')
          .length;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
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
                            'Complaints Dashboard',
                            style: TextStyle(
                              color: Color(0xFF252B36),
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Submit concerns and follow their review and resolution.',
                            style: TextStyle(
                              color: Color(0xFF727B89),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.currentUser.role == AppRoles.parent)
                      FilledButton.icon(
                        onPressed: _addComplaint,
                        icon: const Icon(Icons.add_comment_outlined),
                        label: const Text('New Complaint'),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                        ),
                      ),
                    if (widget.currentUser.role == AppRoles.parent)
                      OutlinedButton.icon(
                        onPressed: () => _importTransfer(response: true),
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Import response'),
                      ),
                    if (widget.canManageRecords)
                      OutlinedButton.icon(
                        onPressed: () => _importTransfer(response: false),
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Import complaint'),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _ComplaintMessage(message: _error!, isError: true),
                ],
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 900 ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 90,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _ComplaintSummary(
                          title: 'Open',
                          value: '$openCount',
                          icon: Icons.mark_unread_chat_alt_outlined,
                          color: widget.primaryColor,
                        ),
                        _ComplaintSummary(
                          title: 'In progress',
                          value: '$inProgressCount',
                          icon: Icons.pending_actions_outlined,
                          color: const Color(0xFFAA6A21),
                        ),
                        _ComplaintSummary(
                          title: 'Resolved / closed',
                          value: '$resolvedCount',
                          icon: Icons.task_alt_rounded,
                          color: const Color(0xFF38805A),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 350,
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Search complainant or complaint',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(_reload),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Status filter',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'All statuses',
                            child: Text('All statuses'),
                          ),
                          ..._statuses.map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(status),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _statusFilter = value;
                            _reload();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (snapshot.hasError)
                  _ComplaintMessage(
                    message:
                        'Complaints could not be loaded: ${snapshot.error}',
                    isError: true,
                    onRetry: () => setState(_reload),
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (complaints.isEmpty)
                  const _EmptyComplaints()
                else
                  _ComplaintsTable(
                    complaints: complaints,
                    canManageRecords: widget.canManageRecords,
                    isParent: widget.currentUser.role == AppRoles.parent,
                    onUpdate: _updateComplaint,
                    onExport: (complaint) => _exportTransfer(
                      complaint,
                      response: !(widget.currentUser.role == AppRoles.parent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ComplaintEntry {
  final String contact;
  final String category;
  final String subject;
  final String description;
  final String priority;

  const _ComplaintEntry({
    required this.contact,
    required this.category,
    required this.subject,
    required this.description,
    required this.priority,
  });
}

class _ComplaintFormDialog extends StatefulWidget {
  final String reporterName;
  final String reporterRole;
  final List<String> categories;
  final List<String> priorities;

  const _ComplaintFormDialog({
    required this.reporterName,
    required this.reporterRole,
    required this.categories,
    required this.priorities,
  });

  @override
  State<_ComplaintFormDialog> createState() => _ComplaintFormDialogState();
}

class _ComplaintFormDialogState extends State<_ComplaintFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _reporterController = TextEditingController(
    text: widget.reporterName,
  );
  final _contactController = TextEditingController();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _category = 'Other';
  String _priority = 'Medium';

  @override
  void dispose() {
    _reporterController.dispose();
    _contactController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _ComplaintEntry(
        contact: _contactController.text.trim(),
        category: _category,
        subject: _subjectController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Submit a complaint'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _reporterController,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Submitting as ${widget.reporterRole}',
                    style: const TextStyle(
                      color: Color(0xFF727B89),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact (optional)',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final category in widget.categories)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: [
                  for (final priority in widget.priorities)
                    DropdownMenuItem(value: priority, child: Text(priority)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _subjectController,
                decoration: const InputDecoration(labelText: 'Subject'),
                validator: _required,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Describe the complaint',
                  alignLabelWithHint: true,
                ),
                minLines: 3,
                maxLines: 5,
                validator: _required,
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
      FilledButton(onPressed: _submit, child: const Text('Submit complaint')),
    ],
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}

class _ComplaintUpdate {
  final String status;
  final String notes;

  const _ComplaintUpdate(this.status, this.notes);
}

class _ComplaintStatusDialog extends StatefulWidget {
  final ComplaintRecord complaint;

  const _ComplaintStatusDialog({required this.complaint});

  @override
  State<_ComplaintStatusDialog> createState() => _ComplaintStatusDialogState();
}

class _ComplaintStatusDialogState extends State<_ComplaintStatusDialog> {
  final _notesController = TextEditingController();
  late String _status = widget.complaint.status;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Update complaint'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'Open', child: Text('Open')),
              DropdownMenuItem(
                value: 'In Progress',
                child: Text('In Progress'),
              ),
              DropdownMenuItem(value: 'Resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'Closed', child: Text('Closed')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Review / resolution notes',
              alignLabelWithHint: true,
            ),
            minLines: 3,
            maxLines: 5,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.of(context)
                .pop(_ComplaintUpdate(_status, _notesController.text)),
        child: const Text('Save update'),
      ),
    ],
  );
}

class _ComplaintsTable extends StatelessWidget {
  final List<ComplaintRecord> complaints;
  final bool canManageRecords;
  final bool isParent;
  final ValueChanged<ComplaintRecord> onUpdate;
  final ValueChanged<ComplaintRecord> onExport;

  const _ComplaintsTable({
    required this.complaints,
    required this.canManageRecords,
    required this.isParent,
    required this.onUpdate,
    required this.onExport,
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
        border: TableBorder.all(color: const Color(0xFFD7DCE3), width: 0.7),
        headingTextStyle: const TextStyle(
          color: Color(0xFF303744),
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
        columns: [
          const DataColumn(label: Center(child: Text('DATE'))),
          const DataColumn(label: Center(child: Text('COMPLAINANT'))),
          const DataColumn(label: Center(child: Text('CATEGORY'))),
          const DataColumn(label: Center(child: Text('SUBJECT'))),
          const DataColumn(label: Center(child: Text('PRIORITY'))),
          const DataColumn(label: Center(child: Text('STATUS'))),
          if (canManageRecords || isParent)
            const DataColumn(label: Center(child: Text('ACTIONS'))),
        ],
        rows: [
          for (final complaint in complaints)
            DataRow(
              cells: [
                DataCell(Text(_dateLabel(complaint.createdAt))),
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      '${complaint.reporterName}\n${complaint.reporterRole}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(complaint.category)),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Tooltip(
                      message: complaint.description,
                      child: Text(
                        complaint.subject,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                DataCell(_PriorityBadge(priority: complaint.priority)),
                DataCell(_ComplaintStatus(status: complaint.status)),
                if (canManageRecords || isParent)
                  DataCell(
                    Wrap(
                      spacing: 4,
                      children: [
                        if (canManageRecords)
                          TextButton.icon(
                            onPressed: () => onUpdate(complaint),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text('Review'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => onExport(complaint),
                          icon: const Icon(Icons.file_download_outlined),
                          label: Text(isParent ? 'Send' : 'Reply'),
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

  static String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _ComplaintSummary extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ComplaintSummary({
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
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 11)),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ComplaintStatus extends StatelessWidget {
  final String status;

  const _ComplaintStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Resolved' || 'Closed' => const Color(0xFF38805A),
      'In Progress' => const Color(0xFFAA6A21),
      _ => const Color(0xFFC62828),
    };
    return _Badge(text: status, color: color);
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;

  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'High' => const Color(0xFFC62828),
      'Medium' => const Color(0xFFAA6A21),
      _ => const Color(0xFF38805A),
    };
    return _Badge(text: priority, color: color);
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );
}

class _ComplaintMessage extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  const _ComplaintMessage({
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

class _EmptyComplaints extends StatelessWidget {
  const _EmptyComplaints();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: const Column(
      children: [
        Icon(Icons.support_agent_rounded, color: Color(0xFFC62828), size: 34),
        SizedBox(height: 10),
        Text(
          'No complaints have been submitted.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          'Use New Complaint to submit a concern for review.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF727B89), fontSize: 12),
        ),
      ],
    ),
  );
}

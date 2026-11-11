import 'package:flutter/material.dart';

import 'auth_repository.dart';
import '../data/student_repository.dart';
import '../student.dart';
import 'app_user.dart';

class UserManagementPage extends StatefulWidget {
  final AppUser currentUser;
  final AuthRepository repository;

  const UserManagementPage({
    super.key,
    required this.currentUser,
    required this.repository,
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  late Future<List<AppUser>> _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _users = widget.repository.getUsers();
  }

  Future<void> _editUser({AppUser? user}) async {
    try {
      final students = await StudentRepository().getAll();
      if (!mounted) return;
      final result = await showDialog<_UserEditorResult>(
        context: context,
        builder: (context) => _UserEditorDialog(
          user: user,
          students: students,
          canEditAccess: user?.id != widget.currentUser.id,
        ),
      );
      if (result == null || !mounted) return;

      if (user == null) {
        await widget.repository.createUser(
          fullName: result.fullName,
          username: result.username,
          password: result.password!,
          role: result.role,
          permissions: result.permissions,
          assignedClassSections: result.assignedClassSections,
          linkedStudentIds: result.linkedStudentIds,
          actorUserId: widget.currentUser.id,
        );
      } else {
        await widget.repository.updateUser(
          user: user.copyWith(
            fullName: result.fullName,
            username: result.username,
            role: result.role,
            permissions: result.permissions,
            assignedClassSections: result.assignedClassSections,
            linkedStudentIds: result.linkedStudentIds,
            isActive: result.isActive,
          ),
          newPassword: result.password,
          actorUserId: widget.currentUser.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _users = widget.repository.getUsers();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(user == null ? 'Account created.' : 'Account updated.'),
        ),
      );
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() => _error = 'Please correct the account details: $error');
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Account changes could not be completed: $error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
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
                        'Users & Roles',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF252B36),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Create staff accounts and control which modules each account can open.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF727B89),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _editUser(),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add user'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              _InlineError(message: _error!),
              const SizedBox(height: 12),
            ],
            FutureBuilder<List<AppUser>>(
              future: _users,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _InlineError(
                    message: 'Could not load accounts: ${snapshot.error}',
                    onRetry: () =>
                        setState(() => _users = widget.repository.getUsers()),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(36),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _accountList(snapshot.data!);
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _accountList(List<AppUser> users) => Card(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE7E9EE)),
    ),
    child: Column(
      children: [
        for (var index = 0; index < users.length; index++) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 7,
            ),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFFBECEC),
              foregroundColor: const Color(0xFFC62828),
              child: Text(
                users[index].fullName.isEmpty
                    ? '?'
                    : users[index].fullName[0].toUpperCase(),
              ),
            ),
            title: Text(
              users[index].fullName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${users[index].username}  •  ${users[index].role}'
              '${users[index].role == AppRoles.teacher ? '  •  ${users[index].assignedClassSections.length} class sections' : ''}'
              '${users[index].role == AppRoles.parent || users[index].role == AppRoles.student ? '  •  ${users[index].linkedStudentIds.length} linked student(s)' : ''}'
              '${users[index].isActive ? '' : '  •  Inactive'}',
            ),
            trailing: const Icon(Icons.edit_outlined, size: 19),
            onTap: () => _editUser(user: users[index]),
          ),
          if (index < users.length - 1)
            const Divider(height: 1, indent: 72, endIndent: 16),
        ],
      ],
    ),
  );
}

class _UserEditorResult {
  final String fullName;
  final String username;
  final String? password;
  final String role;
  final List<String> permissions;
  final List<String> assignedClassSections;
  final List<String> linkedStudentIds;
  final bool isActive;

  const _UserEditorResult({
    required this.fullName,
    required this.username,
    required this.password,
    required this.role,
    required this.permissions,
    required this.assignedClassSections,
    required this.linkedStudentIds,
    required this.isActive,
  });
}

class _UserEditorDialog extends StatefulWidget {
  final AppUser? user;
  final List<Student> students;
  final bool canEditAccess;

  const _UserEditorDialog({
    required this.user,
    required this.students,
    required this.canEditAccess,
  });

  @override
  State<_UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<_UserEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  late String _role;
  late Set<String> _permissions;
  late Set<String> _assignedClassSections;
  late Set<String> _linkedStudentIds;
  late bool _isActive;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _role = user?.role ?? AppRoles.teacher;
    _permissions = Set<String>.from(
      user?.permissions ?? AppRoles.defaultPermissions(_role),
    );
    if (!AppRoles.fullAccessRoles.contains(_role)) {
      _permissions.remove('Users & Roles');
    }
    _assignedClassSections = Set<String>.from(
      user?.assignedClassSections ?? const <String>[],
    );
    _linkedStudentIds = Set<String>.from(
      user?.linkedStudentIds ?? const <String>[],
    );
    _isActive = user?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_permissions.isEmpty) {
      setState(() => _error = 'Select at least one module permission.');
      return;
    }
    if (_role == AppRoles.teacher && _assignedClassSections.isEmpty) {
      setState(() => _error = 'Assign at least one class and section.');
      return;
    }
    if (_role == AppRoles.parent && _linkedStudentIds.isEmpty) {
      setState(() => _error = 'Link at least one student to this parent.');
      return;
    }
    if (_role == AppRoles.student && _linkedStudentIds.length != 1) {
      setState(() => _error = 'Link exactly one student to this account.');
      return;
    }
    Navigator.of(context).pop(
      _UserEditorResult(
        fullName: _nameController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.isEmpty
            ? null
            : _passwordController.text,
        role: _role,
        permissions: AppRoles.modules
            .where(_permissions.contains)
            .toList(growable: false),
        assignedClassSections: _assignedClassSections.toList(growable: false),
        linkedStudentIds: _linkedStudentIds.toList(growable: false),
        isActive: _isActive,
      ),
    );
  }

  void _changeRole(String? role) {
    if (role == null || !widget.canEditAccess) return;
    setState(() {
      _role = role;
      _permissions = Set<String>.from(AppRoles.defaultPermissions(role));
      _assignedClassSections.clear();
      _linkedStudentIds.clear();
    });
  }

  Future<void> _selectClassSections() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _ClassSectionPickerDialog(
        students: widget.students,
        selected: _assignedClassSections,
      ),
    );
    if (result != null) setState(() => _assignedClassSections = result);
  }

  Future<void> _selectLinkedStudents() async {
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _StudentLinkPickerDialog(
        students: widget.students,
        selected: _linkedStudentIds,
        allowMultiple: _role == AppRoles.parent,
      ),
    );
    if (result != null) setState(() => _linkedStudentIds = result);
  }

  @override
  Widget build(BuildContext context) {
    final isNewUser = widget.user == null;
    final title = isNewUser ? 'Create staff account' : 'Edit staff account';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 570,
        height: 540,
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a full name.'
                    : null,
              ),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Use at least 3 characters.'
                    : null,
              ),
              const SizedBox(height: 10),
              if (widget.canEditAccess)
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final role in AppRoles.all)
                      DropdownMenuItem(value: role, child: Text(role)),
                  ],
                  onChanged: _changeRole,
                )
              else
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Role'),
                  child: Text(_role),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: isNewUser ? 'Temporary password' : 'New password',
                  helperText: isNewUser
                      ? 'At least 10 characters. Share it securely with the user.'
                      : 'Leave blank to keep the current password.',
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                obscureText: !_showPassword,
                validator: (value) {
                  if (isNewUser && (value == null || value.length < 10)) {
                    return 'Use at least 10 characters.';
                  }
                  if (value != null && value.isNotEmpty && value.length < 10) {
                    return 'Use at least 10 characters.';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _confirmationController,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                obscureText: !_showPassword,
                validator: (value) {
                  if (isNewUser || _passwordController.text.isNotEmpty) {
                    return value != _passwordController.text
                        ? 'Passwords do not match.'
                        : null;
                  }
                  return null;
                },
              ),
              if (widget.canEditAccess) ...[
                const SizedBox(height: 16),
                if (_role == AppRoles.teacher) ...[
                  OutlinedButton.icon(
                    onPressed: _selectClassSections,
                    icon: const Icon(Icons.class_outlined),
                    label: Text(
                      'Assign classes (${_assignedClassSections.length})',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_role == AppRoles.parent || _role == AppRoles.student) ...[
                  OutlinedButton.icon(
                    onPressed: _selectLinkedStudents,
                    icon: const Icon(Icons.link_rounded),
                    label: Text(
                      'Link student records (${_linkedStudentIds.length})',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const Text(
                  'Module permissions',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                for (final module in AppRoles.modules)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(module, style: const TextStyle(fontSize: 13)),
                    value: _permissions.contains(module),
                    onChanged:
                        AppRoles.fullAccessRoles.contains(_role) ||
                            module == 'Users & Roles'
                        ? null
                        : (checked) => setState(() {
                            if (checked ?? false) {
                              _permissions.add(module);
                            } else {
                              _permissions.remove(module);
                            }
                          }),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Account active'),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Your own role and module permissions can only be changed by another administrator.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF687080)),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                _InlineError(message: _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save account')),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _InlineError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F0),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF1CBCB)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFF9A2222), fontSize: 12),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 10),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    ),
  );
}

class _ClassSectionPickerDialog extends StatefulWidget {
  final List<Student> students;
  final Set<String> selected;

  const _ClassSectionPickerDialog({
    required this.students,
    required this.selected,
  });

  @override
  State<_ClassSectionPickerDialog> createState() =>
      _ClassSectionPickerDialogState();
}

class _ClassSectionPickerDialogState extends State<_ClassSectionPickerDialog> {
  final _searchController = TextEditingController();
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, (String, String)> get _availableClassSections {
    final options = <String, (String, String)>{};
    for (final student in widget.students) {
      final className = student.className.trim();
      final sectionName = student.sectionName.trim();
      if (className.isEmpty) continue;
      final key = '$className\u001f$sectionName';
      options[key] = (className, sectionName);
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final options =
        _availableClassSections.entries
            .where(
              (entry) =>
                  query.isEmpty ||
                  entry.value.$1.toLowerCase().contains(query) ||
                  entry.value.$2.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) {
            final classComparison = a.value.$1.compareTo(b.value.$1);
            return classComparison != 0
                ? classComparison
                : a.value.$2.compareTo(b.value.$2);
          });

    return AlertDialog(
      title: const Text('Assign class sections'),
      content: SizedBox(
        width: 480,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search class or section',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: options.isEmpty
                  ? const Center(child: Text('No class sections found.'))
                  : ListView.builder(
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final label = option.value.$2.isEmpty
                            ? option.value.$1
                            : '${option.value.$1} • ${option.value.$2}';
                        return CheckboxListTile(
                          dense: true,
                          title: Text(label),
                          value: _selected.contains(option.key),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selected.add(option.key);
                            } else {
                              _selected.remove(option.key);
                            }
                          }),
                        );
                      },
                    ),
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
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text('Use ${_selected.length} sections'),
        ),
      ],
    );
  }
}

class _StudentLinkPickerDialog extends StatefulWidget {
  final List<Student> students;
  final Set<String> selected;
  final bool allowMultiple;

  const _StudentLinkPickerDialog({
    required this.students,
    required this.selected,
    required this.allowMultiple,
  });

  @override
  State<_StudentLinkPickerDialog> createState() =>
      _StudentLinkPickerDialogState();
}

class _StudentLinkPickerDialogState extends State<_StudentLinkPickerDialog> {
  final _searchController = TextEditingController();
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final students = widget.students
        .where(
          (student) =>
              query.isEmpty ||
              student.fullName.toLowerCase().contains(query) ||
              student.admissionNumber.toLowerCase().contains(query) ||
              student.className.toLowerCase().contains(query),
        )
        .toList(growable: false);

    return AlertDialog(
      title: Text(
        widget.allowMultiple
            ? 'Link children to parent'
            : 'Link student account',
      ),
      content: SizedBox(
        width: 540,
        height: 470,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search student name or G.R. number',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: students.isEmpty
                  ? const Center(child: Text('No students found.'))
                  : ListView.builder(
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        final subtitle =
                            'G.R. ${student.admissionNumber} • '
                            '${student.className}'
                            '${student.sectionName.trim().isEmpty ? '' : ' • ${student.sectionName}'}';
                        return CheckboxListTile(
                          dense: true,
                          title: Text(student.fullName),
                          subtitle: Text(subtitle),
                          value: _selected.contains(student.studentId),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              if (!widget.allowMultiple) _selected.clear();
                              _selected.add(student.studentId);
                            } else {
                              _selected.remove(student.studentId);
                            }
                          }),
                        );
                      },
                    ),
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
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text('Use ${_selected.length} student(s)'),
        ),
      ],
    );
  }
}

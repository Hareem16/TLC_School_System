import 'package:flutter/material.dart';

import '../auth/app_user.dart';
import '../data/fee_repository.dart';
import '../data/student_repository.dart';
import '../school_profile.dart';
import '../student.dart';

class FamilyDashboardPage extends StatefulWidget {
  final SchoolProfile profile;
  final AppUser user;

  const FamilyDashboardPage({
    super.key,
    required this.profile,
    required this.user,
  });

  @override
  State<FamilyDashboardPage> createState() => _FamilyDashboardPageState();
}

class _FamilyDashboardPageState extends State<FamilyDashboardPage> {
  late Future<_FamilyData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_FamilyData> _load() async {
    final studentIds = widget.user.linkedStudentIds;
    final studentRepository = StudentRepository();
    final linkedStudents = await studentRepository.getAll(
      studentIds: studentIds,
    );
    final students = widget.user.role == AppRoles.parent
        ? await studentRepository.getFamilyMembers(linkedStudents)
        : linkedStudents;
    final charges = await FeeRepository().getMonthlyCharges(
      _currentMonthKey(),
      studentIds: students.map((student) => student.studentId).toList(),
    );
    return _FamilyData(students: students, charges: charges);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_FamilyData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFC62828)),
                const SizedBox(height: 10),
                const Text('Your school records could not be loaded.'),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _data = _load();
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final data = snapshot.data!;
      final totalDue = data.charges.fold<double>(
        0,
        (total, charge) => total + charge.amountDue,
      );
      final totalPaid = data.charges.fold<double>(
        0,
        (total, charge) => total + charge.amountPaid,
      );
      final outstanding = data.charges.fold<double>(
        0,
        (total, charge) => total + charge.balance,
      );
      final chargesByStudent = {
        for (final charge in data.charges) charge.studentId: charge,
      };

      return SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1050),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.user.role == AppRoles.parent
                      ? 'Family dashboard'
                      : 'Student dashboard',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.profile.schoolName}  •  ${_monthLabel(DateTime.now())}',
                  style: const TextStyle(
                    color: Color(0xFF727B89),
                    fontSize: 12,
                  ),
                ),
                if (data.students.any(
                  (student) => student.familyNo.trim().isNotEmpty,
                )) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Family No. ${data.students.map((student) => student.familyNo.trim()).where((familyNo) => familyNo.isNotEmpty).toSet().join(', ')}',
                    style: const TextStyle(
                      color: Color(0xFF687080),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 700 ? 3 : 1;
                    return GridView.count(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 92,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _FamilySummaryCard(
                          title: 'Linked students',
                          value: '${data.students.length}',
                          icon: Icons.school_outlined,
                          color: widget.profile.primaryColor,
                        ),
                        _FamilySummaryCard(
                          title: 'Paid this month',
                          value: _money(totalPaid),
                          icon: Icons.payments_outlined,
                          color: const Color(0xFF38805A),
                        ),
                        _FamilySummaryCard(
                          title: 'Outstanding',
                          value: _money(outstanding),
                          icon: Icons.pending_actions_outlined,
                          color: const Color(0xFFAA6A21),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  'Student accounts',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 12),
                if (data.students.isEmpty)
                  const _FamilyEmptyState()
                else
                  for (final student in data.students)
                    _StudentPortalCard(
                      student: student,
                      charge: chargesByStudent[student.studentId],
                      primaryColor: widget.profile.primaryColor,
                    ),
                if (data.charges.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total billed this month: ${_money(totalDue)}',
                      style: const TextStyle(
                        color: Color(0xFF687080),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E9EE)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: Color(0xFFC62828),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This portal displays students linked to your account and siblings assigned to the same Family No. Contact the school office if a child is missing.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF687080),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  static String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String _monthLabel(DateTime date) {
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
}

class _FamilyData {
  final List<Student> students;
  final List<FeeCharge> charges;

  const _FamilyData({required this.students, required this.charges});
}

class _StudentPortalCard extends StatelessWidget {
  final Student student;
  final FeeCharge? charge;
  final Color primaryColor;

  const _StudentPortalCard({
    required this.student,
    required this.charge,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE7E9EE)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: primaryColor.withValues(alpha: 0.10),
            foregroundColor: primaryColor,
            child: Text(
              student.fullName.isEmpty
                  ? '?'
                  : student.fullName[0].toUpperCase(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'G.R. ${student.admissionNumber}  •  ${student.className}'
                  '${student.sectionName.trim().isEmpty ? '' : ' • ${student.sectionName}'}',
                  style: const TextStyle(
                    color: Color(0xFF687080),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (charge == null)
            const Text(
              'No charge posted this month',
              style: TextStyle(color: Color(0xFF828A98), fontSize: 11),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Due: ${_money(charge!.balance)}',
                  style: TextStyle(
                    color: charge!.balance > 0
                        ? const Color(0xFFAA6A21)
                        : const Color(0xFF38805A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${charge!.status} • ${_money(charge!.amountPaid)} paid',
                  style: const TextStyle(
                    color: Color(0xFF687080),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _FamilySummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _FamilySummaryCard({
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
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF687080), fontSize: 11),
              ),
              const SizedBox(height: 5),
              Text(
                value,
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

class _FamilyEmptyState extends StatelessWidget {
  const _FamilyEmptyState();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: const Text(
      'No student records are linked to this account yet. Please contact the school office.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(0xFF687080), fontSize: 12),
    ),
  );
}

String _money(double value) => 'PKR ${value.toStringAsFixed(2)}';

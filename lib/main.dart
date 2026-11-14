import 'cloud/cloud_account_link_page.dart';
import 'cloud/supabase_service.dart';
import 'cloud/cloud_connection_check.dart';

// import 'cloud/cloud_owner_setup_page.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/app_user.dart';
import 'auth/auth_gate.dart';
import 'attendance/attendance_dashboard.dart';
import 'academic/examinations_page.dart';
import 'academic/question_paper_blueprint_page.dart';
import 'academic/results_page.dart';
import 'auth/user_management_page.dart';
import 'backup/backup_restore_page.dart';
import 'complaints/complaints_page.dart';
import 'auth/auth_repository.dart';
import 'data/app_database.dart';
import 'data/staff_repository.dart';
import 'data/school_profile_repository.dart';
import 'data/student_repository.dart';
import 'fees/fee_vouchers_page.dart';
import 'families/family_dashboard_page.dart';
import 'families/families_page.dart';
import 'ece/ece_activities_page.dart';
import 'inventory/inventory_page.dart';
import 'library/library_page.dart';
import 'notices/notices_page.dart';
import 'payroll/payroll_page.dart';
import 'reports/reports_page.dart';
import 'school_profile.dart';
import 'staff/staff_page.dart';
import 'student.dart';
import 'students_page.dart';
import 'timetable/timetable_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize cloud services without blocking offline app usage.
  await SupabaseService.initialize();

  runApp(const TLCSchoolApp());

  // Run a read-only cloud diagnostic without blocking the app interface.
  unawaited(CloudConnectionCheck.run());
  // unawaited(_testWindowsDeviceRegistration());
  // unawaited(_checkDeviceIdentity());
}

class TLCSchoolApp extends StatefulWidget {
  final AuthRepository? authRepository;

  const TLCSchoolApp({super.key, this.authRepository});

  @override
  State<TLCSchoolApp> createState() => _TLCSchoolAppState();
}

class _TLCSchoolAppState extends State<TLCSchoolApp> {
  SchoolProfile profile = SchoolProfile.tlc();
  final SchoolProfileRepository _profileRepository = SchoolProfileRepository();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final savedProfile = await _profileRepository.load();
    if (mounted && savedProfile != null) {
      setState(
        () => profile = savedProfile.copyWith(
          // Keep the saved school's own theme. Only supply the bundled TLC
          // logo when no logo path has been configured yet.
          logoPath: savedProfile.logoPath.isEmpty
              ? 'assets/images/tlc_logo.png'
              : savedProfile.logoPath,
        ),
      );
    }
  }

  void updateProfile(SchoolProfile updated) {
    setState(() => profile = updated);
    unawaited(_profileRepository.save(updated));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TLC School System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: profile.primaryColor,
          primary: profile.primaryColor,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        fontFamily: 'Arial',
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: AuthGate(
        profile: profile,
        repository: widget.authRepository,
        homeBuilder: (user, onSignOut, repository) => TLCHome(
          profile: profile,
          user: user,
          authRepository: repository,
          onSignOut: onSignOut,
          onProfileChanged: updateProfile,
        ),
      ),
      // home: const CloudOwnerSetupPage(),
    );
  }
}

class TLCHome extends StatefulWidget {
  final SchoolProfile profile;
  final AppUser user;
  final AuthRepository authRepository;
  final VoidCallback onSignOut;
  final ValueChanged<SchoolProfile> onProfileChanged;

  const TLCHome({
    super.key,
    required this.profile,
    required this.user,
    required this.authRepository,
    required this.onSignOut,
    required this.onProfileChanged,
  });

  @override
  State<TLCHome> createState() => _TLCHomeState();
}

class _TLCHomeState extends State<TLCHome> {
  String selected = 'Dashboard';
  int _mobileTab = 0;
  final StudentRepository _studentRepository = StudentRepository();
  final StaffRepository _staffRepository = StaffRepository();
  late Future<(List<Student>, List<StaffMember>, int)> _dashboardData;
  late Future<Map<String, Object?>> _dashboardInsightsData;

  final List<(String, List<(String, IconData)>)> menuGroups = [
    (
      'WORKSPACE',
      [
        ('Dashboard', Icons.dashboard_rounded),
        ('Students', Icons.school_rounded),
      ],
    ),
    (
      'SCHOOL',
      [
        ('Teachers & Staff', Icons.people_rounded),
        ('Payroll', Icons.payments_outlined),
        ('Attendance', Icons.fact_check_rounded),
        ('Time-Table', Icons.calendar_month_rounded),
        ('Examinations', Icons.assignment_rounded),
        ('Results & Report Cards', Icons.bar_chart_rounded),
        ('Complaints', Icons.support_agent_rounded),
      ],
    ),
    (
      'ADMINISTRATION',
      [
        ('Fees & Vouchers', Icons.receipt_long_rounded),
        ('Inventory', Icons.inventory_2_rounded),
        ('Library', Icons.menu_book_rounded),
        ('Question Paper Maker', Icons.edit_document),
        ('ECE Activities', Icons.toys_rounded),
        ('Notices', Icons.campaign_rounded),
        ('Reports', Icons.assessment_rounded),
        ('Users & Roles', Icons.manage_accounts_rounded),
        ('Siblings & Families', Icons.family_restroom_rounded),
        ('Backup & Restore', Icons.backup_rounded),
        ('Cloud Account & Sync', Icons.cloud_sync_rounded),
      ],
    ),
  ];

  List<(String, List<(String, IconData)>)> get visibleMenuGroups => [
    for (final group in menuGroups)
      if (group.$2.any((item) => _canOpen(item.$1)))
        (
          group.$1,
          group.$2.where((item) => _canOpen(item.$1)).toList(growable: false),
        ),
  ];

  bool _canOpen(String module) {
    if (module == 'Cloud Account & Sync') return true;
    if (module == 'Backup & Restore' &&
        !AppRoles.fullAccessRoles.contains(widget.user.role)) {
      return false;
    }
    if (module == 'Siblings & Families' &&
        !AppRoles.fullAccessRoles.contains(widget.user.role)) {
      return false;
    }
    if (module == 'Complaints' &&
        widget.user.role != AppRoles.parent &&
        !AppRoles.fullAccessRoles.contains(widget.user.role)) {
      return false;
    }
    if (module == 'Payroll' &&
        !AppRoles.fullAccessRoles.contains(widget.user.role)) {
      return false;
    }
    return widget.user.canAccess(module) &&
        (module != 'Users & Roles' ||
            AppRoles.fullAccessRoles.contains(widget.user.role));
  }

  List<String>? get _teacherClassScope => widget.user.role == AppRoles.teacher
      ? widget.user.assignedClassSections
      : null;

  List<String>? get _familyStudentScope =>
      widget.user.role == AppRoles.parent ||
          widget.user.role == AppRoles.student
      ? widget.user.linkedStudentIds
      : null;

  Future<(List<Student>, List<StaffMember>, int)> _loadDashboardData() async {
    final students = widget.user.canAccess('Students')
        ? await _studentRepository.getAll(
            classSectionKeys: _teacherClassScope,
            studentIds: _familyStudentScope,
          )
        : const <Student>[];
    final staff = _canOpen('Teachers & Staff')
        ? await _staffRepository.getAll()
        : const <StaffMember>[];
    final userCount = _canOpen('Users & Roles')
        ? (await widget.authRepository.getUsers()).length
        : 0;
    return (students, staff, userCount);
  }

  @override
  void initState() {
    super.initState();
    selected = _canOpen('Dashboard')
        ? 'Dashboard'
        : AppRoles.modules.firstWhere(_canOpen, orElse: () => '');
    _dashboardData = _loadDashboardData();
    _dashboardInsightsData = _canViewDashboardInsights
        ? _loadDashboardInsights()
        : Future.value(const <String, Object?>{});
  }

  void _selectMenu(String name) {
    if (!_canOpen(name)) return;
    setState(() {
      selected = name;
      _mobileTab = 0;
      if (name == 'Dashboard' && widget.user.canAccess('Students')) {
        _dashboardData = _loadDashboardData();
        _dashboardInsightsData = _canViewDashboardInsights
            ? _loadDashboardInsights()
            : Future.value(const <String, Object?>{});
      }
    });
  }

  bool get _canViewDashboardInsights =>
      AppRoles.fullAccessRoles.contains(widget.user.role);

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;

    if (MediaQuery.sizeOf(context).width < 760) {
      return _mobileShell(p);
    }

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 258,
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFF0D7D7),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset(
                              'assets/images/tlc_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.school_rounded,
                                    color: p.primaryColor,
                                    size: 27,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'TLC SCHOOL',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.primaryColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        p.schoolName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFC62828),
                          height: 1.35,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE9EBEF)),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                    children: [
                      for (final group in visibleMenuGroups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 7),
                          child: Text(
                            group.$1,
                            style: const TextStyle(
                              color: Color(0xFF9299A5),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        for (final item in group.$2)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Material(
                              color: selected == item.$1
                                  ? p.primaryColor.withValues(alpha: 0.09)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: ListTile(
                                dense: true,
                                minLeadingWidth: 22,
                                selected: selected == item.$1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                leading: Icon(
                                  item.$2,
                                  size: 19,
                                  color: selected == item.$1
                                      ? p.primaryColor
                                      : const Color(0xFF77808E),
                                ),
                                title: Text(
                                  item.$1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selected == item.$1
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected == item.$1
                                        ? p.primaryColor
                                        : const Color(0xFF414956),
                                  ),
                                ),
                                onTap: () => _selectMenu(item.$1),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE9EBEF)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    children: [
                      if (_canOpen('School Profile & Settings'))
                        Material(
                          color: selected == 'School Profile & Settings'
                              ? p.primaryColor.withValues(alpha: 0.09)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            leading: Icon(
                              Icons.settings_outlined,
                              color: selected == 'School Profile & Settings'
                                  ? p.primaryColor
                                  : const Color(0xFF77808E),
                            ),
                            title: const Text(
                              'School Profile & Settings',
                              style: TextStyle(fontSize: 12),
                            ),
                            selected: selected == 'School Profile & Settings',
                            onTap: () =>
                                _selectMenu('School Profile & Settings'),
                          ),
                        ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: p.primaryColor.withValues(
                              alpha: 0.10,
                            ),
                            child: Icon(
                              Icons.person_outline,
                              size: 17,
                              color: p.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              widget.user.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF414956),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sign out',
                            onPressed: widget.onSignOut,
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            color: const Color(0xFF77808E),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        SchoolProfile.developerCreditText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFC62828),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF252B36),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${p.schoolName}  •  ${p.academicYear}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF828A98),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _todayLabel(),
                        style: const TextStyle(
                          color: Color(0xFF687080),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.user.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            widget.user.role,
                            style: const TextStyle(
                              color: Color(0xFF828A98),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: widget.onSignOut,
                        icon: const Icon(Icons.logout_rounded),
                        color: p.primaryColor,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _wallpaperBackground(selected, _selectedContent(p)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedContent(SchoolProfile p) {
    if (selected == 'Cloud Account & Sync') {
      return CloudAccountLinkPage(
        localUser: widget.user,
        primaryColor: p.primaryColor,
      );
    }
    if (selected == 'School Profile & Settings') {
      return SchoolSettingsPage(
        profile: p,
        onSave: (updated) {
          widget.onProfileChanged(updated);
          _selectMenu('Dashboard');
        },
      );
    }
    if (selected == 'Backup & Restore' && _canOpen('Backup & Restore')) {
      return BackupRestorePage(primaryColor: p.primaryColor);
    }
    if (selected == 'Users & Roles' && _canOpen('Users & Roles')) {
      return UserManagementPage(
        currentUser: widget.user,
        repository: widget.authRepository,
      );
    }
    if (selected == 'Attendance' && _canOpen('Attendance')) {
      return AttendanceDashboard(classSectionKeys: _teacherClassScope);
    }
    if (selected == 'Time-Table' && _canOpen('Time-Table')) {
      return TimetableDashboard(user: widget.user);
    }
    if (selected == 'Students' && _canOpen('Students')) {
      return StudentsPage(
        primaryColor: p.primaryColor,
        profile: p,
        classSectionKeys: _teacherClassScope,
        studentIds: _familyStudentScope,
        canManageRecords: AppRoles.fullAccessRoles.contains(widget.user.role),
      );
    }
    if (selected == 'Fees & Vouchers' && _canOpen('Fees & Vouchers')) {
      return FeeVouchersPage(
        user: widget.user,
        profile: p,
        primaryColor: p.primaryColor,
        allowedStudentIds: _familyStudentScope,
        canManageCharges: AppRoles.fullAccessRoles.contains(widget.user.role),
        canAcceptPayments:
            AppRoles.fullAccessRoles.contains(widget.user.role) ||
            widget.user.role == AppRoles.frontDeskOfficer,
      );
    }
    if (selected == 'Siblings & Families' && _canOpen('Siblings & Families')) {
      return const FamiliesPage();
    }
    if (selected == 'Complaints' && _canOpen('Complaints')) {
      return ComplaintsPage(
        currentUser: widget.user,
        primaryColor: p.primaryColor,
        canManageRecords: AppRoles.fullAccessRoles.contains(widget.user.role),
      );
    }
    if (selected == 'Inventory' && _canOpen('Inventory')) {
      return InventoryPage(primaryColor: p.primaryColor, profile: p);
    }
    if (selected == 'Teachers & Staff' && _canOpen('Teachers & Staff')) {
      return StaffPage(
        primaryColor: p.primaryColor,
        profile: p,
        canManageRecords: AppRoles.fullAccessRoles.contains(widget.user.role),
        canViewSalary: AppRoles.fullAccessRoles.contains(widget.user.role),
      );
    }
    if (selected == 'Payroll' && _canOpen('Payroll')) {
      return PayrollPage(profile: p);
    }
    if (selected == 'Library' && _canOpen('Library')) {
      return LibraryPage(
        primaryColor: p.primaryColor,
        canManageRecords: AppRoles.fullAccessRoles.contains(widget.user.role),
      );
    }
    if (selected == 'Examinations' && _canOpen('Examinations')) {
      return ExaminationsPage(user: widget.user, profile: p);
    }
    if (selected == 'Results & Report Cards' &&
        _canOpen('Results & Report Cards')) {
      return ResultsPage(user: widget.user, profile: p);
    }
    if (selected == 'Question Paper Maker' &&
        _canOpen('Question Paper Maker')) {
      return const QuestionPaperBlueprintPage();
    }
    if (selected == 'ECE Activities' && _canOpen('ECE Activities')) {
      return const EceActivitiesPage();
    }
    if (selected == 'Notices' && _canOpen('Notices')) {
      return NoticesPage(user: widget.user, profile: p);
    }
    if (selected == 'Reports' && _canOpen('Reports')) {
      return ReportsPage(user: widget.user, profile: p);
    }
    if (selected == 'Dashboard' &&
        (widget.user.role == AppRoles.parent ||
            widget.user.role == AppRoles.student)) {
      return FamilyDashboardPage(profile: p, user: widget.user);
    }
    if (selected == 'Dashboard') return _dashboard(p);
    return _placeholder(p);
  }

  Widget _mobileShell(SchoolProfile p) {
    final page = switch (_mobileTab) {
      0 => selected == 'Dashboard' ? _mobileDashboard(p) : _selectedContent(p),
      1 =>
        _canOpen('Time-Table')
            ? TimetableDashboard(user: widget.user)
            : _mobileUnavailable('Time-Table'),
      2 =>
        _canOpen('Attendance')
            ? AttendanceDashboard(classSectionKeys: _teacherClassScope)
            : _mobileUnavailable('Attendance'),
      _ => _mobileProfile(p),
    };
    final needsTopBar =
        _mobileTab == 0 && selected == 'Dashboard' || _mobileTab == 3;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: needsTopBar
          ? AppBar(
              backgroundColor: p.primaryColor,
              foregroundColor: Colors.white,
              title: Text(
                _mobileTab == 3 ? 'My Profile' : 'TLC School System',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: widget.onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            )
          : null,
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileTab,
        onDestinationSelected: (index) {
          if (index == 1 && !_canOpen('Time-Table')) {
            _mobileMessage('Your account does not have timetable access.');
            return;
          }
          if (index == 2 && !_canOpen('Attendance')) {
            _mobileMessage('Your account does not have attendance access.');
            return;
          }
          setState(() {
            _mobileTab = index;
            if (index == 0) selected = 'Dashboard';
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _mobileDashboard(SchoolProfile p) {
    const modules = <(String, IconData, Color)>[
      (
        'Fees & Vouchers',
        Icons.account_balance_wallet_outlined,
        Color(0xFF3498DB),
      ),
      ('Students', Icons.school_outlined, Color(0xFF536D9B)),
      ('Attendance', Icons.fact_check_outlined, Color(0xFFE91E63)),
      ('Notices', Icons.campaign_outlined, Color(0xFFD47782)),
      ('Examinations', Icons.assignment_turned_in_outlined, Color(0xFFF4B400)),
      ('Teachers & Staff', Icons.people_outline, Color(0xFF7042B5)),
      ('Results & Report Cards', Icons.description_outlined, Color(0xFFF57C00)),
      ('Time-Table', Icons.calendar_month_outlined, Color(0xFF00A8B5)),
      ('ECE Activities', Icons.draw_outlined, Color(0xFF43A047)),
      ('Library', Icons.menu_book_outlined, Color(0xFFE53935)),
      ('Inventory', Icons.inventory_2_outlined, Color(0xFF795548)),
      ('Complaints', Icons.support_agent_outlined, Color(0xFF8E24AA)),
      ('Reports', Icons.analytics_outlined, Color(0xFF546E7A)),
      ('Payroll', Icons.payments_outlined, Color(0xFF00897B)),
      ('Question Paper Maker', Icons.edit_document, Color(0xFF673AB7)),
      ('Users & Roles', Icons.manage_accounts_outlined, Color(0xFF455A64)),
      ('Backup & Restore', Icons.backup_outlined, Color(0xFF2E7D32)),
      ('School Profile & Settings', Icons.settings_outlined, Color(0xFF8D6E63)),
    ];
    final visible = modules.where((item) => _canOpen(item.$1)).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.primaryColor, const Color(0xFF8E1717)],
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, color: p.primaryColor),
                    ),
                  ],
                ),
                Text(
                  'TLC School System',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Good ${DateTime.now().hour < 12
                      ? 'Morning'
                      : DateTime.now().hour < 17
                      ? 'Afternoon'
                      : 'Evening'}, ${widget.user.role}',
                  style: const TextStyle(color: Colors.white70, fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  p.academicYear,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<(List<Student>, List<StaffMember>, int)>(
            future: _dashboardData,
            builder: (context, snapshot) {
              final students =
                  snapshot.data?.$1
                      .where((student) => student.dateOfRemoval == null)
                      .length ??
                  0;
              final staff = snapshot.data?.$2.length ?? 0;
              return Row(
                children: [
                  if (_canOpen('Students'))
                    Expanded(
                      child: _mobileMetric(
                        Icons.school_outlined,
                        '$students',
                        'Students',
                        const Color(0xFFC62828),
                      ),
                    ),
                  if (_canOpen('Teachers & Staff')) const SizedBox(width: 10),
                  if (_canOpen('Teachers & Staff'))
                    Expanded(
                      child: _mobileMetric(
                        Icons.people_outline,
                        '$staff',
                        'Staff',
                        const Color(0xFF7042B5),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'School modules',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.84,
            children: [
              for (final item in visible)
                _mobileTile(item.$1, item.$2, item.$3),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 60,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final pair in [
                  (22.0, const Color(0xFFB9C3E8)),
                  (42.0, const Color(0xFFFFC078)),
                  (54.0, const Color(0xFFEF91A9)),
                  (36.0, const Color(0xFF9DD9CC)),
                  (28.0, const Color(0xFFF5D47C)),
                  (58.0, const Color(0xFFBDA7E8)),
                ])
                  Container(
                    width: 17,
                    height: pair.$1,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: pair.$2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileMetric(
    IconData icon,
    String value,
    String label,
    Color color,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
      ],
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _mobileTile(String name, IconData icon, Color color) => Material(
    color: color,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _selectMenu(name),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              name.replaceAll(' & ', '\n& ').replaceAll(' and ', '\n'),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _mobileProfile(SchoolProfile p) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      CircleAvatar(
        radius: 40,
        backgroundColor: p.primaryColor.withValues(alpha: 0.12),
        child: Icon(Icons.person, size: 40, color: p.primaryColor),
      ),
      const SizedBox(height: 12),
      Center(
        child: Text(
          widget.user.fullName,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      Center(child: Text(widget.user.role)),
      const SizedBox(height: 22),
      Card(
        child: ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: const Text('Username'),
          subtitle: Text(widget.user.username),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.school_outlined),
          title: Text(p.schoolName),
          subtitle: Text(p.academicYear),
        ),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: widget.onSignOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );

  Widget _mobileUnavailable(String name) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Your account does not have access to $name.',
        textAlign: TextAlign.center,
      ),
    ),
  );
  void _mobileMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
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
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  Widget _wallpaperBackground(String section, Widget child) {
    const wallpaperBySection = {
      'Dashboard': 'dashboard_wallpaper.png',
      'School Profile & Settings': 'dashboard_wallpaper.png',
      'Users & Roles': 'dashboard_wallpaper.png',
      'Students': 'studentsrecord_wallpaper.png',
      'Teachers & Staff': 'staff_wallpaper.png',
      'Attendance': 'attendance_wallpaper.png',
      'Time-Table': 'timetables_wallpaper.png',
      'Examinations': 'exams_wallpaper.png',
      'Results & Report Cards': 'results_wallpapers.png',
      'Fees & Vouchers': 'complaints_wallpaper.png',
      'Siblings & Families': 'studentsrecord_wallpaper.png',
      'Inventory': 'inventory_wallpaper.png',
      'Library': 'classroom_wallpaper.png',
      'Question Paper Maker': 'exams_wallpaper.png',
      'ECE Activities': 'classroom_wallpaper.png',
      'Notices': 'notices_wallpaper.png',
      'Complaints': 'complaints_wallpaper.png',
      'Reports': 'results_wallpapers.png',
    };
    final wallpaper = wallpaperBySection[section] ?? 'dashboard_wallpaper.png';
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/backgrounds/$wallpaper'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.white.withValues(alpha: 0.76),
            BlendMode.srcOver,
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _dashboard(SchoolProfile p) {
    return FutureBuilder<(List<Student>, List<StaffMember>, int)>(
      future: _dashboardData,
      builder: (context, snapshot) {
        final canViewStudents = widget.user.canAccess('Students');
        final students = snapshot.data?.$1 ?? const <Student>[];
        final staff = snapshot.data?.$2 ?? const <StaffMember>[];
        final userCount = snapshot.data?.$3 ?? 0;
        final activeStudents = students
            .where((student) => student.dateOfRemoval == null)
            .toList();
        final boys = activeStudents
            .where((student) => _isGender(student.gender, 'boy', 'male'))
            .length;
        final girls = activeStudents
            .where((student) => _isGender(student.gender, 'girl', 'female'))
            .length;
        final classes = activeStudents
            .map((student) => student.className)
            .where((className) => className.trim().isNotEmpty)
            .toSet()
            .length;
        final quickAccessCards = <Widget>[
          if (canViewStudents)
            _quickAccessCard(
              title: 'Student records',
              subtitle: 'Search, manage, import, and export student files',
              icon: Icons.school_outlined,
              color: p.primaryColor,
              onTap: () => _selectMenu('Students'),
            ),
          if (_canOpen('Fees & Vouchers'))
            _quickAccessCard(
              title: 'Fees & vouchers',
              subtitle: 'Monthly charges, payments, and receipts',
              icon: Icons.receipt_long_outlined,
              color: const Color(0xFF38805A),
              onTap: () => _selectMenu('Fees & Vouchers'),
            ),
          if (_canOpen('Siblings & Families'))
            _quickAccessCard(
              title: 'Siblings & families',
              subtitle: 'Import family numbers and link sibling records',
              icon: Icons.family_restroom_outlined,
              color: const Color(0xFFAA6A21),
              onTap: () => _selectMenu('Siblings & Families'),
            ),
          if (_canOpen('Complaints'))
            _quickAccessCard(
              title: 'Complaints',
              subtitle: 'Log, review, and follow up on school concerns',
              icon: Icons.support_agent_rounded,
              color: const Color(0xFFAA6A21),
              onTap: () => _selectMenu('Complaints'),
            ),
          if (_canOpen('Teachers & Staff'))
            _quickAccessCard(
              title: 'Teachers & staff',
              subtitle: 'Employee register and monthly salary profiles',
              icon: Icons.people_outline_rounded,
              color: const Color(0xFF576D91),
              onTap: () => _selectMenu('Teachers & Staff'),
            ),
          if (_canOpen('Payroll'))
            _quickAccessCard(
              title: 'Teacher payroll',
              subtitle: 'Monthly salary sheet and printable slips',
              icon: Icons.payments_outlined,
              color: const Color(0xFF00897B),
              onTap: () => _selectMenu('Payroll'),
            ),
          if (_canOpen('Examinations'))
            _quickAccessCard(
              title: 'Examinations',
              subtitle: 'Manage exams, subjects, totals, and marks',
              icon: Icons.assignment_outlined,
              color: const Color(0xFFC62828),
              onTap: () => _selectMenu('Examinations'),
            ),
          if (_canOpen('Results & Report Cards'))
            _quickAccessCard(
              title: 'Results & report cards',
              subtitle: 'Print student cards and class tabulation',
              icon: Icons.bar_chart_rounded,
              color: const Color(0xFFF57C00),
              onTap: () => _selectMenu('Results & Report Cards'),
            ),
          if (_canOpen('ECE Activities'))
            _quickAccessCard(
              title: 'ECE worksheets',
              subtitle: 'Create or import C.W. / H.W. worksheets',
              icon: Icons.draw_outlined,
              color: const Color(0xFF43A047),
              onTap: () => _selectMenu('ECE Activities'),
            ),
          if (_canOpen('Notices'))
            _quickAccessCard(
              title: 'Official notices',
              subtitle: 'Prepare school-branded notices for sharing',
              icon: Icons.campaign_outlined,
              color: const Color(0xFFAA6A21),
              onTap: () => _selectMenu('Notices'),
            ),
          if (_canOpen('Reports'))
            _quickAccessCard(
              title: 'Reports',
              subtitle: 'Filter and export school record packs',
              icon: Icons.assessment_outlined,
              color: const Color(0xFF576D91),
              onTap: () => _selectMenu('Reports'),
            ),
          if (_canOpen('Question Paper Maker'))
            _quickAccessCard(
              title: 'Question paper blueprint',
              subtitle: 'Review the planned paper creation workflow',
              icon: Icons.edit_document,
              color: const Color(0xFF6D647E),
              onTap: () => _selectMenu('Question Paper Maker'),
            ),
          if (_canOpen('Inventory'))
            _quickAccessCard(
              title: 'Inventory',
              subtitle: 'Stock levels, receipts, and issue history',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFFAA6A21),
              onTap: () => _selectMenu('Inventory'),
            ),
          if (_canOpen('Library'))
            _quickAccessCard(
              title: 'Library & book lists',
              subtitle: 'Class-wise book register and curriculum lists',
              icon: Icons.menu_book_outlined,
              color: const Color(0xFF6D647E),
              onTap: () => _selectMenu('Library'),
            ),
          if (_canOpen('Users & Roles'))
            _quickAccessCard(
              title: 'Users & roles',
              subtitle: 'Manage staff accounts and permissions',
              icon: Icons.manage_accounts_outlined,
              color: const Color(0xFF576D91),
              onTap: () => _selectMenu('Users & Roles'),
            ),
          if (_canOpen('School Profile & Settings'))
            _quickAccessCard(
              title: 'School profile',
              subtitle: 'Update school details and theme',
              icon: Icons.domain_outlined,
              color: const Color(0xFF6D647E),
              onTap: () => _selectMenu('School Profile & Settings'),
            ),

          if (_canOpen('Attendance'))
            _quickAccessCard(
              title: 'Attendance',
              subtitle: 'Daily attendance and class-wise records',
              icon: Icons.fact_check_outlined,
              color: const Color(0xFFC62828),
              onTap: () => _selectMenu('Attendance'),
            ),

          if (_canOpen('Time-Table'))
            _quickAccessCard(
              title: 'Time-Table',
              subtitle: 'Class, teacher, assessment and exam schedules',
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFF576D91),
              onTap: () => _selectMenu('Time-Table'),
            ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.schoolName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC62828),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${widget.user.role == AppRoles.administrator ? 'Admin' : widget.user.role} Dashboard',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF252B36),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.user.fullName}  •  Academic year ${p.academicYear}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF727B89),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_canOpen('School Profile & Settings'))
                        OutlinedButton.icon(
                          onPressed: () =>
                              _selectMenu('School Profile & Settings'),
                          icon: const Icon(Icons.tune_rounded, size: 17),
                          label: const Text('School settings'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _welcomeCard(p),
                  if (canViewStudents) ...[
                    const SizedBox(height: 27),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Student overview',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF252B36),
                            ),
                          ),
                        ),
                        if (snapshot.connectionState == ConnectionState.done &&
                            !snapshot.hasError)
                          Text(
                            '${students.length} records',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF828A98),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    if (snapshot.connectionState != ConnectionState.done)
                      const SizedBox(
                        height: 120,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.hasError)
                      _dashboardError()
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 1050
                              ? 4
                              : constraints.maxWidth >= 620
                              ? 2
                              : 1;
                          return GridView.count(
                            crossAxisCount: columns,
                            crossAxisSpacing: 13,
                            mainAxisSpacing: 13,
                            mainAxisExtent: 112,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _statCard(
                                'Total students',
                                '${activeStudents.length}',
                                Icons.school_outlined,
                                p.primaryColor,
                                'Currently enrolled',
                              ),
                              _statCard(
                                'Boys',
                                '$boys',
                                Icons.male_rounded,
                                const Color(0xFF8E1717),
                                'Active student records',
                              ),
                              _statCard(
                                'Girls',
                                '$girls',
                                Icons.female_rounded,
                                const Color(0xFFC62828),
                                'Active student records',
                              ),
                              _statCard(
                                'Classes',
                                '$classes',
                                Icons.meeting_room_outlined,
                                const Color(0xFFAA3333),
                                'With active students',
                              ),
                              if (_canOpen('Teachers & Staff'))
                                _statCard(
                                  'Teachers & staff',
                                  '${staff.length}',
                                  Icons.people_outline_rounded,
                                  const Color(0xFF576D91),
                                  'Employee register',
                                ),
                              if (_canOpen('Users & Roles'))
                                _statCard(
                                  'System users',
                                  '$userCount',
                                  Icons.manage_accounts_outlined,
                                  const Color(0xFF38805A),
                                  'Accounts with role access',
                                ),
                              if (_canOpen('Students'))
                                _statCard(
                                  'Removed records',
                                  '${students.length - activeStudents.length}',
                                  Icons.delete_outline_rounded,
                                  const Color(0xFF9A4D4D),
                                  'Retained student history',
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: 28),
                  const Text(
                    'Master control panel',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF252B36),
                    ),
                  ),
                  const SizedBox(height: 13),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (quickAccessCards.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final columns = constraints.maxWidth >= 850 ? 3 : 1;
                      return GridView.count(
                        crossAxisCount: columns,
                        crossAxisSpacing: 13,
                        mainAxisSpacing: 13,
                        mainAxisExtent: 106,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: quickAccessCards,
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  if (canViewStudents && activeStudents.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _classDistribution(activeStudents, p.primaryColor),
                  ],
                  const SizedBox(height: 20),
                  if (AppRoles.fullAccessRoles.contains(widget.user.role))
                    _dashboardInsights()
                  else
                    _dashboardRoleCard(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isGender(String value, String first, String second) {
    final normalized = value.trim().toLowerCase();
    return normalized == first || normalized == second;
  }

  Widget _welcomeCard(SchoolProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [profile.primaryColor, const Color(0xFF8E1717)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: profile.primaryColor.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Image.asset(
              'assets/images/tlc_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.school_rounded,
                size: 30,
                color: profile.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.schoolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (profile.motto.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    profile.motto,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFCE8E8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Text(
              profile.academicYear,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color color,
    String helper,
  ) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF252B36),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF525B69),
                  ),
                ),
                Text(
                  helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9299A5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAccessCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7E9EE)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF303744),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF828A98),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF9AA1AB),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Student totals could not be loaded.',
              style: TextStyle(color: Color(0xFF687080), fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _dashboardData = _loadDashboardData();
              });
            },
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _classDistribution(List<Student> students, Color color) {
    final counts = <String, int>{};
    for (final student in students) {
      final className = student.className.trim();
      if (className.isNotEmpty) {
        counts.update(className, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final sorted = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final visible = sorted.take(8).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final maximum = visible.first.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Student population by class',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF252B36),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Live count from active student records',
            style: TextStyle(fontSize: 11, color: Color(0xFF828A98)),
          ),
          const SizedBox(height: 18),
          for (final entry in visible) ...[
            Row(
              children: [
                SizedBox(
                  width: 75,
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF414956),
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: constraints.maxWidth * entry.value / maximum,
                        height: 13,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${entry.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF414956),
                    ),
                  ),
                ),
              ],
            ),
            if (entry != visible.last) const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }

  Future<Map<String, Object?>> _loadDashboardInsights() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final month = today.substring(0, 7);
    final attendance = await db.rawQuery(
      '''
      SELECT s.class_name AS class_name,
        SUM(CASE WHEN LOWER(a.status) IN ('present','p') THEN 1 ELSE 0 END) AS present,
        COUNT(*) AS total
      FROM attendance a JOIN students s ON s.student_id = a.student_id
      WHERE a.attendance_date = ?
      GROUP BY s.class_name ORDER BY s.class_name
    ''',
      [today],
    );
    final fees = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count FROM fee_charges c
      WHERE c.month_key = ?
        AND COALESCE((SELECT SUM(p.amount) FROM fee_payments p
                      WHERE p.fee_id = c.fee_id), 0)
            - COALESCE((SELECT SUM(r.amount)
                        FROM fee_payment_reversals r
                        JOIN fee_payments p ON p.payment_id = r.payment_id
                        WHERE p.fee_id = c.fee_id), 0) < c.amount_due
    ''',
      [month],
    );
    final recent = await db.rawQuery('''
      SELECT * FROM (
        SELECT 'Student' AS type, first_name || ' ' || last_name AS name, created_at AS at FROM students
        UNION ALL
        SELECT 'Teacher' AS type, full_name AS name, created_at AS at FROM staff
        UNION ALL
        SELECT 'Fee' AS type, receipt_number AS name, paid_at AS at FROM fee_payments
        UNION ALL
        SELECT 'Fee correction' AS type, p.receipt_number AS name,
               r.reversed_at AS at
        FROM fee_payment_reversals r
        JOIN fee_payments p ON p.payment_id = r.payment_id
        UNION ALL
        SELECT 'Notice' AS type, title AS name, created_at AS at FROM school_notices
      ) ORDER BY at DESC LIMIT 7
    ''');
    return {
      'attendance': attendance,
      'unpaidFees': fees.length,
      'recent': recent,
    };
  }

  Widget _dashboardInsights() => FutureBuilder<Map<String, Object?>>(
    future: _dashboardInsightsData,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final attendance = (snapshot.data!['attendance'] as List)
          .cast<Map<String, Object?>>();
      final recent = (snapshot.data!['recent'] as List)
          .cast<Map<String, Object?>>();
      final unpaidFees = snapshot.data!['unpaidFees'] as int;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 900;
              final chart = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE7E9EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attendance by class (today)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (attendance.isEmpty)
                      const Text(
                        'No attendance has been recorded today.',
                        style: TextStyle(
                          color: Color(0xFF828A98),
                          fontSize: 12,
                        ),
                      ),
                    for (final row in attendance) ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: Text(
                              '${row['class_name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final total = row['total'] as int;
                                final present = row['present'] as int;
                                final ratio = total == 0
                                    ? 0.0
                                    : present / total;
                                return Stack(
                                  children: [
                                    Container(
                                      width: box.maxWidth,
                                      height: 13,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE9EDF3),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    Container(
                                      width: box.maxWidth * ratio,
                                      height: 13,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF5C9CE6),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '${row['present']}/${row['total']} present',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                    ],
                  ],
                ),
              );
              final alerts = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE7E9EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System alerts',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _alertTile(
                      Icons.money_off_csred_outlined,
                      '$unpaidFees unpaid fee records',
                      unpaidFees == 0
                          ? 'Current month is clear'
                          : 'Review the fee ledger',
                      const Color(0xFFC62828),
                    ),
                    const SizedBox(height: 8),
                    _alertTile(
                      Icons.cloud_off_outlined,
                      'Local data storage',
                      'This device has no automatic cloud sync',
                      const Color(0xFF65758B),
                    ),
                  ],
                ),
              );
              return stacked
                  ? Column(
                      children: [chart, const SizedBox(height: 12), alerts],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: chart),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: alerts),
                      ],
                    );
            },
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE7E9EE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent records',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                if (recent.isEmpty)
                  const Text('No recent records are available.'),
                for (final row in recent)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: _recordIcon('${row['type']}'),
                    title: Text(
                      '${row['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${row['type']} · ${row['at']}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: const Icon(Icons.more_horiz, size: 18),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _dashboardRoleCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE7E9EE)),
    ),
    child: Row(
      children: [
        const Icon(Icons.verified_user_outlined, color: Color(0xFFC62828)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Dashboard data is limited to the records and modules assigned to your account.',
            style: const TextStyle(color: Color(0xFF596273), fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _alertTile(IconData icon, String title, String detail, Color color) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF828A98),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _recordIcon(String type) {
    final (icon, color) = switch (type) {
      'Student' => (Icons.school_outlined, const Color(0xFF4779BC)),
      'Teacher' => (Icons.people_outline, const Color(0xFFB97155)),
      'Fee' => (Icons.receipt_long_outlined, const Color(0xFF38805A)),
      _ => (Icons.campaign_outlined, const Color(0xFF7E57C2)),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, size: 17, color: color),
    );
  }

  Widget _placeholder(SchoolProfile p) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7E9EE)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: p.primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.construction_rounded,
                size: 27,
                color: p.primaryColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              selected,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF252B36),
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'This section is planned but is not available yet. The current app is being built module by module.',
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: Color(0xFF727B89),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _selectMenu('Dashboard'),
              icon: const Icon(Icons.arrow_back_rounded, size: 17),
              label: const Text('Back to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class SchoolSettingsPage extends StatefulWidget {
  final SchoolProfile profile;
  final ValueChanged<SchoolProfile> onSave;

  const SchoolSettingsPage({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<SchoolSettingsPage> createState() => _SchoolSettingsPageState();
}

class _SchoolSettingsPageState extends State<SchoolSettingsPage> {
  late final TextEditingController nameController;
  late final TextEditingController mottoController;
  late final TextEditingController yearController;
  late final TextEditingController addressController;
  late final TextEditingController phoneController;
  late final TextEditingController bankNameController;
  late final TextEditingController bankAccountController;
  late final TextEditingController logoController;

  late Color primaryColor;
  late Color secondaryColor;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    nameController = TextEditingController(text: p.schoolName);
    mottoController = TextEditingController(text: p.motto);
    yearController = TextEditingController(text: p.academicYear);
    addressController = TextEditingController(text: p.address);
    phoneController = TextEditingController(text: p.phone);
    bankNameController = TextEditingController(text: p.bankName);
    bankAccountController = TextEditingController(text: p.bankAccount);
    logoController = TextEditingController(text: p.logoPath);
    primaryColor = p.primaryColor;
    secondaryColor = p.secondaryColor;
  }

  @override
  void dispose() {
    nameController.dispose();
    mottoController.dispose();
    yearController.dispose();
    addressController.dispose();
    phoneController.dispose();
    bankNameController.dispose();
    bankAccountController.dispose();
    logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE6E8EF)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'School Profile & Settings',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure the identity and appearance of this school.',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 25),
                  _field('School Name', nameController),
                  _field('School Motto', mottoController),
                  _field('Academic Year (e.g. 2026–2027)', yearController),
                  _field('School Address', addressController),
                  _field('School Contact Number', phoneController),
                  _field('Fee Voucher Bank Name', bankNameController),
                  _field(
                    'Fee Voucher Bank Account Number',
                    bankAccountController,
                  ),
                  _field(
                    'Logo File Path (optional)',
                    logoController,
                    hint: 'Example: assets/images/tlc_logo.png',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'School Theme',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _themeOption(
                        'TLC Red & White',
                        const Color(0xFFC62828),
                        const Color(0xFF8E1717),
                      ),
                      _themeOption(
                        'Ocean Blue',
                        const Color(0xFF1565C0),
                        const Color(0xFF0D47A1),
                      ),
                      _themeOption(
                        'Emerald Green',
                        const Color(0xFF16845B),
                        const Color(0xFF075B3B),
                      ),
                      _themeOption(
                        'Royal Purple',
                        const Color(0xFF7045A5),
                        const Color(0xFF482477),
                      ),
                      _themeOption(
                        'Warm Gold',
                        const Color(0xFFB7791F),
                        const Color(0xFF805515),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, secondaryColor],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nameController.text.isEmpty
                              ? 'School Name Preview'
                              : nameController.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mottoController.text,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Academic Year: ${yearController.text}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save School Profile'),
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'School profile changes are saved for this installation. '
                    'The TLC logo is included with the app.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeOption(String label, Color primary, Color secondary) {
    final isSelected = primaryColor == primary && secondaryColor == secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        primaryColor = primary;
        secondaryColor = secondary;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.07) : Colors.white,
          border: Border.all(
            color: isSelected ? primary : const Color(0xFFE3E6EC),
            width: isSelected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 8, backgroundColor: primary),
            const SizedBox(width: 5),
            CircleAvatar(radius: 8, backgroundColor: secondary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
            if (isSelected) ...[
              const SizedBox(width: 5),
              Icon(Icons.check_circle, size: 15, color: primary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  void _save() {
    if (nameController.text.trim().isEmpty ||
        yearController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the school name and academic year.'),
        ),
      );
      return;
    }

    final updated = widget.profile.copyWith(
      schoolName: nameController.text.trim(),
      motto: mottoController.text.trim(),
      academicYear: yearController.text.trim(),
      address: addressController.text.trim(),
      phone: phoneController.text.trim(),
      bankName: bankNameController.text.trim(),
      bankAccount: bankAccountController.text.trim(),
      logoPath: logoController.text.trim(),
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );

    widget.onSave(updated);
  }
}

// Future<void> _checkDeviceIdentity() async {
//   try {
//     final first = await DeviceIdentityService.getOrCreate();
//     final second = await DeviceIdentityService.getOrCreate();

//     print('========== TLC DEVICE IDENTITY TEST ==========');
//     print('Device name: ${first.deviceName}');
//     print('Platform: ${first.platform}');
//     print('Device ID: ${first.deviceKey}');
//     print('Same ID on second request: ${first.deviceKey == second.deviceKey}');
//     final cloudClient = SupabaseService.client;
//     final cloudUser = cloudClient?.auth.currentUser;

//     print('---------- SUPABASE OWNER CHECK ----------');

//     if (cloudClient != null && cloudUser != null) {
//       print('Signed-in email: ${cloudUser.email}');
//       print('Supabase user ID: ${cloudUser.id}');
//       print(
//         'Correct owner account: '
//         '${cloudUser.id == '13be2536-c081-4cd0-9d59-0f3190b63219'}',
//       );

//       final memberships = await cloudClient
//           .from('school_memberships')
//           .select('school_id, role, is_active')
//           .eq('school_id', 'b0d10576-b910-4cd3-8300-c1a727e9d510')
//           .eq('user_id', cloudUser.id);

//       print('School membership: $memberships');
//     } else {
//       print('No active Supabase sign-in session found.');
//     }

//     print('------------------------------------------');
//     print('==============================================');
//   } catch (error) {
//     print('TLC DEVICE IDENTITY TEST FAILED: $error');
//   }
// }

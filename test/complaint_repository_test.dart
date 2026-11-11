import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tlc_school_system/auth/app_user.dart';
import 'package:tlc_school_system/data/complaint_repository.dart';

Future<Database> _database() async => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(
    version: 1,
    onCreate: (database, version) => database.execute('''
      CREATE TABLE complaints (
        complaint_id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL DEFAULT '',
        reporter_name TEXT NOT NULL,
        reporter_role TEXT NOT NULL,
        contact TEXT NOT NULL,
        category TEXT NOT NULL,
        subject TEXT NOT NULL,
        description TEXT NOT NULL,
        priority TEXT NOT NULL,
        status TEXT NOT NULL,
        resolution_notes TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    '''),
  ),
);

AppUser _user(String id, String role) => AppUser(
  id: id,
  fullName: '$role $id',
  username: id,
  role: role,
  permissions: AppRoles.defaultPermissions(role),
  isActive: true,
);

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'complaints stay private and transfer between parent and admin devices',
    () async {
      final parentDb = await _database();
      final schoolDb = await _database();
      addTearDown(parentDb.close);
      addTearDown(schoolDb.close);
      final parent = _user('family-1', AppRoles.parent);
      final otherParent = _user('family-2', AppRoles.parent);
      final administrator = _user('administrator-1', AppRoles.administrator);
      final teacher = _user('teacher-1', AppRoles.teacher);
      final parentRepository = ComplaintRepository(
        databaseProvider: () async => parentDb,
      );
      final schoolRepository = ComplaintRepository(
        databaseProvider: () async => schoolDb,
      );

      await parentRepository.create(
        currentUser: parent,
        contact: '03000000000',
        category: 'Academic',
        subject: 'Bus timing',
        description: 'Please confirm the afternoon route time.',
        priority: 'Medium',
      );
      final parentComplaints = await parentRepository.getAll(
        currentUser: parent,
      );
      expect(parentComplaints, hasLength(1));
      expect(await parentRepository.getAll(currentUser: otherParent), isEmpty);
      await expectLater(
        parentRepository.getAll(currentUser: teacher),
        throwsStateError,
      );
      await expectLater(
        parentRepository.updateStatus(
          currentUser: parent,
          complaintId: parentComplaints.single.id,
          status: 'Resolved',
          resolutionNotes: 'Done',
        ),
        throwsStateError,
      );

      await parentDb.insert('complaints', {
        'complaint_id': 'legacy-unowned',
        'owner_user_id': '',
        'reporter_name': 'Legacy reporter',
        'reporter_role': AppRoles.parent,
        'contact': '',
        'category': 'Other',
        'subject': 'Old complaint',
        'description': 'Imported from the earlier database.',
        'priority': 'Low',
        'status': 'Open',
        'resolution_notes': '',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      expect(await parentRepository.getAll(currentUser: parent), hasLength(1));
      expect(
        await parentRepository.getAll(currentUser: administrator),
        hasLength(2),
      );

      final submission = await parentRepository.exportSubmissionJson(
        currentUser: parent,
        complaintId: parentComplaints.single.id,
      );
      await schoolRepository.importSubmissionJson(
        currentUser: administrator,
        contents: submission,
      );
      final received = await schoolRepository.getAll(
        currentUser: administrator,
      );
      final imported = received.singleWhere(
        (complaint) => complaint.subject == 'Bus timing',
      );
      await schoolRepository.updateStatus(
        currentUser: administrator,
        complaintId: imported.id,
        status: 'Resolved',
        resolutionNotes: 'The updated schedule is posted at the school office.',
      );
      final response = await schoolRepository.exportResponseJson(
        currentUser: administrator,
        complaintId: imported.id,
      );
      await parentRepository.importResponseJson(
        currentUser: parent,
        contents: response,
      );
      final resolved = await parentRepository.getAll(currentUser: parent);
      expect(resolved.single.status, 'Resolved');
      expect(
        resolved.single.resolutionNotes,
        'The updated schedule is posted at the school office.',
      );
    },
  );
}

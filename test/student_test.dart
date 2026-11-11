import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/student.dart';

void main() {
  group('Student database mapping', () {
    test('round-trips the complete student master record', () {
      final student = Student(
        studentId: 'student-1',
        admissionNumber: 'GR-001',
        rollNumber: '12',
        firstName: 'Amina',
        lastName: '',
        className: 'Class 3',
        sectionName: '',
        guardianName: 'Usman',
        guardianPhone: '03001234567',
        gender: 'Girl',
        religion: 'Islam',
        dateOfBirth: DateTime(2018, 4, 12),
        placeOfBirth: 'Lahore',
        address: 'Main Street',
        dateOfAdmission: DateTime(2024, 8, 1),
        previousInstitute: 'City School',
        admittedClass: 'Class 3',
        dateOfRemoval: DateTime(2025, 5, 31),
        classAtRemoval: 'Class 3',
        causeOfRemoval: 'Relocation',
        remarks: 'Transferred',
        monthlyFee: 1250.50,
        createdAt: DateTime(2024, 8, 1),
      );

      final restored = Student.fromDatabaseMap(student.toDatabaseMap());

      expect(restored.studentName, 'Amina');
      expect(restored.admissionNumber, 'GR-001');
      expect(restored.rollNumber, '12');
      expect(restored.gender, 'Girl');
      expect(restored.dateOfBirth, DateTime(2018, 4, 12));
      expect(restored.dateOfAdmission, DateTime(2024, 8, 1));
      expect(restored.dateOfRemoval, DateTime(2025, 5, 31));
      expect(restored.monthlyFee, 1250.50);
      expect(restored.remarks, 'Transferred');
    });

    test('reads records created before the master-record migration', () {
      final restored = Student.fromDatabaseMap({
        'student_id': 'legacy-student',
        'admission_number': 'GR-OLD',
        'first_name': 'Sara',
        'last_name': 'Khan',
        'class_name': 'Class 2',
        'section_name': null,
        'guardian_name': 'Ahmed Khan',
        'guardian_phone': null,
        'created_at': DateTime(2023, 1, 10).toIso8601String(),
      });

      expect(restored.studentName, 'Sara Khan');
      expect(restored.rollNumber, isEmpty);
      expect(restored.gender, 'Unknown');
      expect(restored.monthlyFee, 0);
      expect(restored.dateOfBirth, isNull);
    });
  });
}

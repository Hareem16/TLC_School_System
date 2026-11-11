class Student {
  final String studentId;
  final String admissionNumber;
  final String rollNumber;
  final String firstName;
  final String lastName;
  final String className;
  final String sectionName;
  final String guardianName;
  final String guardianPhone;
  final String gender;
  final String religion;
  final DateTime? dateOfBirth;
  final String placeOfBirth;
  final String address;
  final String familyNo;
  final DateTime? dateOfAdmission;
  final String previousInstitute;
  final String admittedClass;
  final DateTime? dateOfRemoval;
  final String classAtRemoval;
  final String causeOfRemoval;
  final String remarks;
  final double monthlyFee;
  final DateTime createdAt;

  const Student({
    required this.studentId,
    required this.admissionNumber,
    this.rollNumber = '',
    required this.firstName,
    required this.lastName,
    required this.className,
    required this.sectionName,
    required this.guardianName,
    required this.guardianPhone,
    this.gender = 'Unknown',
    this.religion = '',
    this.dateOfBirth,
    this.placeOfBirth = '',
    this.address = '',
    this.familyNo = '',
    this.dateOfAdmission,
    this.previousInstitute = '',
    this.admittedClass = '',
    this.dateOfRemoval,
    this.classAtRemoval = '',
    this.causeOfRemoval = '',
    this.remarks = '',
    this.monthlyFee = 0,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get studentName => fullName;

  Map<String, Object?> toDatabaseMap() => {
    'student_id': studentId,
    'admission_number': admissionNumber,
    'roll_number': rollNumber,
    'first_name': firstName,
    'last_name': lastName,
    'class_name': className,
    'section_name': sectionName,
    'guardian_name': guardianName,
    'guardian_phone': guardianPhone,
    'gender': gender,
    'religion': religion,
    'date_of_birth': dateOfBirth?.toIso8601String(),
    'place_of_birth': placeOfBirth,
    'address': address,
    'family_no': familyNo,
    'date_of_admission': dateOfAdmission?.toIso8601String(),
    'previous_institute': previousInstitute,
    'admitted_class': admittedClass,
    'date_of_removal': dateOfRemoval?.toIso8601String(),
    'class_at_removal': classAtRemoval,
    'cause_of_removal': causeOfRemoval,
    'remarks': remarks,
    'monthly_fee': monthlyFee,
    'created_at': createdAt.toIso8601String(),
  };

  factory Student.fromDatabaseMap(Map<String, Object?> map) => Student(
    studentId: map['student_id']! as String,
    admissionNumber: map['admission_number']! as String,
    rollNumber: (map['roll_number'] as String?) ?? '',
    firstName: map['first_name']! as String,
    lastName: map['last_name']! as String,
    className: map['class_name']! as String,
    sectionName: (map['section_name'] as String?) ?? '',
    guardianName: (map['guardian_name'] as String?) ?? '',
    guardianPhone: (map['guardian_phone'] as String?) ?? '',
    gender: (map['gender'] as String?) ?? 'Unknown',
    religion: (map['religion'] as String?) ?? '',
    dateOfBirth: _dateFromDatabase(map['date_of_birth']),
    placeOfBirth: (map['place_of_birth'] as String?) ?? '',
    address: (map['address'] as String?) ?? '',
    familyNo: (map['family_no'] as String?) ?? '',
    dateOfAdmission: _dateFromDatabase(map['date_of_admission']),
    previousInstitute: (map['previous_institute'] as String?) ?? '',
    admittedClass: (map['admitted_class'] as String?) ?? '',
    dateOfRemoval: _dateFromDatabase(map['date_of_removal']),
    classAtRemoval: (map['class_at_removal'] as String?) ?? '',
    causeOfRemoval: (map['cause_of_removal'] as String?) ?? '',
    remarks: (map['remarks'] as String?) ?? '',
    monthlyFee: (map['monthly_fee'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.parse(map['created_at']! as String),
  );

  static DateTime? _dateFromDatabase(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

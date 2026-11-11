import 'package:flutter/material.dart';

class SchoolProfile {
  static const developerCreditText = 'Developed By: FAKHRA RASHID';

  final String schoolId;
  final String schoolName;
  final String motto;
  final String developerCredit;
  final String academicYear;
  final String address;
  final String phone;
  final String bankName;
  final String bankAccount;
  final String logoPath;
  final Color primaryColor;
  final Color secondaryColor;

  const SchoolProfile({
    required this.schoolId,
    required this.schoolName,
    required this.motto,
    required this.developerCredit,
    required this.academicYear,
    required this.address,
    required this.phone,
    required this.bankName,
    required this.bankAccount,
    required this.logoPath,
    required this.primaryColor,
    required this.secondaryColor,
  });

  factory SchoolProfile.tlc() {
    return const SchoolProfile(
      schoolId: 'tlc-secondary-school',
      schoolName: 'THE LEARNING CIRCLE SECONDARY SCHOOL',
      motto: "Let's Make It Happens!",
      developerCredit: developerCreditText,
      academicYear: '2026–2027',
      address: '',
      phone: '',
      bankName: 'Bank Al-Habib Ltd.',
      bankAccount: '1164-0981-003052-01-2',
      logoPath: 'assets/images/tlc_logo.png',
      primaryColor: Color(0xFFC62828),
      secondaryColor: Color(0xFF8E1717),
    );
  }

  SchoolProfile copyWith({
    String? schoolName,
    String? motto,
    String? academicYear,
    String? address,
    String? phone,
    String? bankName,
    String? bankAccount,
    String? logoPath,
    Color? primaryColor,
    Color? secondaryColor,
  }) {
    return SchoolProfile(
      schoolId: schoolId,
      schoolName: schoolName ?? this.schoolName,
      motto: motto ?? this.motto,
      developerCredit: developerCredit,
      academicYear: academicYear ?? this.academicYear,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      bankName: bankName ?? this.bankName,
      bankAccount: bankAccount ?? this.bankAccount,
      logoPath: logoPath ?? this.logoPath,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
    );
  }

  Map<String, Object?> toDatabaseMap() => {
    'school_id': schoolId,
    'school_name': schoolName,
    'motto': motto,
    'developer_credit': developerCredit,
    'academic_year': academicYear,
    'address': address,
    'phone': phone,
    'bank_name': bankName,
    'bank_account': bankAccount,
    'logo_path': logoPath,
    'primary_color': primaryColor.toARGB32(),
    'secondary_color': secondaryColor.toARGB32(),
  };

  factory SchoolProfile.fromDatabaseMap(Map<String, Object?> map) {
    return SchoolProfile(
      schoolId: map['school_id']! as String,
      schoolName: map['school_name']! as String,
      motto: map['motto']! as String,
      developerCredit: map['developer_credit']! as String,
      academicYear: map['academic_year']! as String,
      address: map['address']! as String,
      phone: map['phone']! as String,
      bankName: (map['bank_name'] as String?) ?? 'Bank Al-Habib Ltd.',
      bankAccount: (map['bank_account'] as String?) ?? '1164-0981-003052-01-2',
      logoPath: map['logo_path']! as String,
      primaryColor: Color(map['primary_color']! as int),
      secondaryColor: Color(map['secondary_color']! as int),
    );
  }
}

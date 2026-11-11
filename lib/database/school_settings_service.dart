import 'package:flutter/material.dart';

import '../school_profile.dart';
import 'app_database.dart';

class SchoolSettingsService {
  SchoolSettingsService._();

  static final SchoolSettingsService instance = SchoolSettingsService._();

  Future<void> save(SchoolProfile profile) async {
    await AppDatabase.instance.saveSchoolSettings({
      'school_id': profile.schoolId,
      'school_name': profile.schoolName,
      'motto': profile.motto,
      'academic_year': profile.academicYear,
      'address': profile.address,
      'phone': profile.phone,
      'logo_path': profile.logoPath,
      'primary_color': profile.primaryColor.toARGB32(),
      'secondary_color': profile.secondaryColor.toARGB32(),
    });
  }

  Future<SchoolProfile?> load() async {
    final data = await AppDatabase.instance.loadSchoolSettings(
      SchoolProfile.tlc().schoolId,
    );

    if (data == null) {
      return null;
    }

    return SchoolProfile.tlc().copyWith(
      schoolName: data['school_name'] as String,
      motto: data['motto'] as String,
      academicYear: data['academic_year'] as String,
      address: data['address'] as String,
      phone: data['phone'] as String,
      logoPath: data['logo_path'] as String,
      primaryColor: Color(data['primary_color'] as int),
      secondaryColor: Color(data['secondary_color'] as int),
    );
  }
}

String formatAcademicYear(Object? value) =>
    (value ?? '').toString().replaceAllMapped(
      RegExp(r'(\d{4})\s*[-–—/]\s*(\d{4})'),
      (match) => '${match[1]} - ${match[2]}',
    );

String formatReportCardExamHeading({
  required Object? examName,
  required Object? academicYear,
}) {
  final normalizedName = (examName ?? '')
      .toString()
      .replaceAll(RegExp(r'\(?\b\d{4}\s*[-–—/]\s*\d{4}\b\)?'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s\-–—:()]+$'), '')
      .trim()
      .toUpperCase();
  final year = formatAcademicYear(academicYear);
  return [normalizedName, year].where((part) => part.isNotEmpty).join(' ');
}

String formatReportCardSchoolName(String schoolName) {
  return schoolName.trim().replaceAll(RegExp(r'\s+'), ' ');
}

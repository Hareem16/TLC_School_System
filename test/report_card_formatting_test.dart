import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/academic/report_card_formatting.dart';

void main() {
  test('keeps the academic year once in the report-card exam heading', () {
    expect(
      formatReportCardExamHeading(
        examName: 'Mid-Term Examination 2026-2027',
        academicYear: '2026–2027',
      ),
      'MID-TERM EXAMINATION 2026 - 2027',
    );
  });

  test('keeps the school name on one line', () {
    expect(
      formatReportCardSchoolName('THE LEARNING CIRCLE SECONDARY SCHOOL'),
      'THE LEARNING CIRCLE SECONDARY SCHOOL',
    );
  });

  test('preserves school names without the standard suffix', () {
    expect(formatReportCardSchoolName('TLC Academy'), 'TLC Academy');
  });
}

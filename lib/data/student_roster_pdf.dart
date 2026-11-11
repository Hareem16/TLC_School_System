import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../school_profile.dart';
import '../student.dart';

class StudentRosterPdf {
  static Future<Uint8List> build({
    required SchoolProfile profile,
    required List<Student> students,
  }) async {
    final logoBytes = (await rootBundle.load('assets/images/tlc_logo.png'))
        .buffer
        .asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final document = pw.Document();
    final accent = PdfColor.fromInt(profile.primaryColor.toARGB32());

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        header: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Row(
            children: [
              pw.Image(logo, width: 42, height: 42),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      profile.schoolName,
                      style: pw.TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'STUDENT REGISTER • ${profile.academicYear}',
                      style: pw.TextStyle(
                        color: PdfColors.grey700,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Text(
                'Records: ${students.length}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            '${profile.developerCredit}  •  Page ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.8),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(0.7),
              3: pw.FlexColumnWidth(0.9),
              4: pw.FlexColumnWidth(1.4),
              5: pw.FlexColumnWidth(1.3),
              6: pw.FlexColumnWidth(0.9),
            },
            children: [
              _tableRow(
                [
                  'G.R. No.',
                  'Student',
                  'Gender',
                  'Class',
                  'Father / Guardian',
                  'Contact',
                  'Monthly Fee',
                ],
                header: true,
                accent: accent,
              ),
              for (final student in students)
                _tableRow([
                  student.admissionNumber,
                  student.fullName,
                  student.gender,
                  '${student.className}${student.sectionName.isEmpty ? '' : ' - ${student.sectionName}'}',
                  student.guardianName,
                  student.guardianPhone,
                  'PKR ${student.monthlyFee.toStringAsFixed(2)}',
                ], header: false, accent: accent),
            ],
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.TableRow _tableRow(
    List<String> values, {
    required bool header,
    required PdfColor accent,
  }) => pw.TableRow(
    decoration: header ? pw.BoxDecoration(color: accent) : null,
    children: values
        .map(
          (value) => pw.Padding(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                color: header ? PdfColors.white : PdfColors.grey900,
                fontSize: 7,
                fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        )
        .toList(growable: false),
  );
}

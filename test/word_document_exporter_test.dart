import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tlc_school_system/data/word_document_exporter.dart';
import 'package:tlc_school_system/school_profile.dart';

void main() {
  test('creates an Office Open XML Word document with a table', () {
    final bytes = WordDocumentExporter.encodeTable(
      profile: SchoolProfile.tlc(),
      title: 'Student Register',
      headers: const ['Student', 'Class'],
      rows: const [
        ['Amina & Sara', 'Class 3'],
      ],
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final document = archive.findFile('word/document.xml');

    expect(document, isNotNull);
    expect(document!.content, isNotEmpty);
  });

  test('rejects table rows that do not match the header shape', () {
    expect(
      () => WordDocumentExporter.encodeTable(
        profile: SchoolProfile.tlc(),
        title: 'Student Register',
        headers: const ['Student', 'Class'],
        rows: const [
          ['Amina'],
        ],
      ),
      throwsArgumentError,
    );
  });
}

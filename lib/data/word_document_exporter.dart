import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../school_profile.dart';

class WordDocumentExporter {
  static Uint8List encodeTable({
    required SchoolProfile profile,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    bool landscape = false,
  }) {
    if (headers.isEmpty || rows.any((row) => row.length != headers.length)) {
      throw ArgumentError('Every Word table row must match its header count.');
    }
    final archive = Archive()
      ..addFile(_file('[Content_Types].xml', _contentTypes))
      ..addFile(_file('_rels/.rels', _packageRelationships))
      ..addFile(
        _file(
          'word/document.xml',
          _documentXml(
            profile: profile,
            title: title,
            headers: headers,
            rows: rows,
            landscape: landscape,
          ),
        ),
      );
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw StateError('The Word document could not be encoded.');
    return Uint8List.fromList(bytes);
  }

  static ArchiveFile _file(String path, String contents) {
    final bytes = utf8.encode(contents);
    return ArchiveFile(path, bytes.length, bytes);
  }

  static String _documentXml({
    required SchoolProfile profile,
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required bool landscape,
  }) {
    final accent = profile.primaryColor.toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    final columns = headers.length;
    final columnWidth = (landscape ? 16838 : 11906) ~/ columns;
    final tableRows = <String>[
      _tableRow(
        headers,
        columnWidth: columnWidth,
        header: true,
        accent: accent,
      ),
      for (final row in rows)
        _tableRow(row, columnWidth: columnWidth, header: false, accent: accent),
    ];
    final addressLine = [
      profile.address.trim(),
      profile.phone.trim(),
    ].where((value) => value.isNotEmpty).join(' • ');
    final addressParagraph = addressLine.isEmpty
        ? ''
        : _paragraph(addressLine, size: 18, centered: true);
    return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${_paragraph(profile.schoolName, size: 30, bold: true, color: accent, centered: true)}
    $addressParagraph
    ${_paragraph(title, size: 24, bold: true, color: accent, centered: true)}
    <w:tbl>
      <w:tblPr>
        <w:tblBorders>
          <w:top w:val="single" w:sz="6" w:color="D5D9E0"/>
          <w:left w:val="single" w:sz="6" w:color="D5D9E0"/>
          <w:bottom w:val="single" w:sz="6" w:color="D5D9E0"/>
          <w:right w:val="single" w:sz="6" w:color="D5D9E0"/>
          <w:insideH w:val="single" w:sz="4" w:color="D5D9E0"/>
          <w:insideV w:val="single" w:sz="4" w:color="D5D9E0"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid>${List.filled(columns, '<w:gridCol w:w="$columnWidth"/>').join()}</w:tblGrid>
      ${tableRows.join()}
    </w:tbl>
    ${_paragraph(profile.developerCredit, size: 16, bold: true, centered: true)}
    <w:sectPr>
      <w:pgSz w:w="${landscape ? 16838 : 11906}" w:h="${landscape ? 11906 : 16838}"${landscape ? ' w:orient="landscape"' : ''}/>
      <w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720"/>
    </w:sectPr>
  </w:body>
</w:document>
''';
  }

  static String _tableRow(
    List<String> cells, {
    required int columnWidth,
    required bool header,
    required String accent,
  }) {
    final cellXml = cells.map((value) {
      final fill = header
          ? '<w:shd w:fill="$accent"/>'
          : '';
      final color = header ? 'FFFFFF' : '252B36';
      return '''
<w:tc>
  <w:tcPr><w:tcW w:w="$columnWidth" w:type="dxa"/>$fill</w:tcPr>
  <w:p><w:r><w:rPr>${header ? '<w:b/>' : ''}<w:color w:val="$color"/></w:rPr><w:t xml:space="preserve">${_escape(value)}</w:t></w:r></w:p>
</w:tc>''';
    }).join();
    return '<w:tr>$cellXml</w:tr>';
  }

  static String _paragraph(
    String text, {
    int size = 20,
    bool bold = false,
    String? color,
    bool centered = false,
  }) => '''
<w:p>${centered ? '<w:pPr><w:jc w:val="center"/></w:pPr>' : ''}<w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="$size"/>${color == null ? '' : '<w:color w:val="$color"/>'}</w:rPr><w:t xml:space="preserve">${_escape(text)}</w:t></w:r></w:p>''';

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static const _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

  static const _packageRelationships = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';
}

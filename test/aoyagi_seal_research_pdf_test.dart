import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('research: real Aoyagi Reisho PDF rejects missing glyphs', () async {
    final coverageFile = File('build/aoyagi-seal-fixture/coverage.json');
    final coverage = jsonDecode(coverageFile.readAsStringSync()) as Map;
    final codepoints = (coverage['codepoints'] as List).cast<int>().toSet();
    final fontBytes = File('test/fixtures/aoyagi-reisho/AoyagiReisho.ttf')
        .readAsBytesSync();
    final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
    final samples = coverage['samples'] as List;
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index] as Map;
      final name = sample['name'] as String;
      final missing = name.runes.where((rune) => !codepoints.contains(rune));
      if (missing.isNotEmpty) {
        expect(index, 3);
        expect(String.fromCharCodes(missing), '𠮷');
        continue;
      }
      final characters = name.runes.map(String.fromCharCode).toList();
      final rowCount = (characters.length / 3).ceil();
      final cellSize = 150 / rowCount;
      final document = pw.Document();
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(children: [
          pw.Text('Aoyagi Reisho / research only / sample ${index + 1}'),
          pw.SizedBox(height: 20),
          pw.Text(name, style: pw.TextStyle(font: font, fontSize: 18)),
          pw.SizedBox(height: 20),
          pw.Container(
            width: 164,
            height: 164,
            padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.red, width: 2)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: List.generate(3, (column) => pw.Column(
                children: List.generate(rowCount, (row) {
                  final offset = (2 - column) * rowCount + row;
                  return pw.SizedBox(
                    width: cellSize,
                    height: cellSize,
                    child: pw.Center(child: pw.Text(
                      offset < characters.length ? characters[offset] : '',
                      style: pw.TextStyle(font: font,
                          fontSize: cellSize * 0.88, color: PdfColors.red),
                    )),
                  );
                }),
              )),
            ),
          ),
        ]),
      ));
      final bytes = await document.save();
      expect(bytes.length, greaterThan(1000));
      File('build/aoyagi-seal-fixture/aoyagi_reisho_$index.pdf')
          .writeAsBytesSync(bytes);
    }
    expect(File('build/aoyagi-seal-fixture/aoyagi_reisho_3.pdf').existsSync(),
        isFalse);
  }, skip: !File('build/aoyagi-seal-fixture/coverage.json').existsSync()
      ? 'Independent research workflow prepares coverage; no product change.'
      : false);
}

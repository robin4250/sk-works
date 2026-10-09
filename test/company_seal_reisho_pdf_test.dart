import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/shared/company_seal_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genuine Reisho preserves names, rejects missing glyphs and keeps legacy opt-in', () async {
    const longName = '合同会社長い会社名建設工業サービスSKO';
    expect(CompanySealPdf.balancedColumns(longName).join(), longName);
    expect(await CompanySealPdf.unsupportedReishoCharacters('株式会社𠮷野'), '𠮷');
    final font = await CompanySealPdf.loadStyleFont(CompanySealPdf.reishoStyle);
    expect(() => CompanySealPdf.build('株式会社𠮷野', font: font,
        style: CompanySealPdf.reishoStyle), throwsStateError);
    expect(() => CompanySealPdf.build('株式会社テスト', font: font,
        style: 'tensho'), throwsStateError);
    expect(CompanySealPdf.reishoGlyphSize(longName, 32), lessThan(4.5));
    expect(() => CompanySealPdf.build(longName, font: font,
        style: CompanySealPdf.reishoStyle), throwsStateError);
    expect(() => CompanySealPdf.build('株式会社テスト建設', size: 12, font: font,
        style: CompanySealPdf.reishoStyle), throwsStateError);
    expect(CompanySealPdf.reishoGlyphSize('株式会社テスト建設', 32), greaterThan(4.5));
    final usage = await rootBundle.loadString(
        'assets/fonts/company-seal/aoyagi-reisho/FONT-USAGE-utf8.txt');
    expect(usage, contains('再配布にあたって有料とすることはできません'));
    final explanation = await rootBundle.load(
        'assets/fonts/company-seal/aoyagi-reisho/FONT-EXPLANATION-original.pdf');
    expect(explanation.lengthInBytes, greaterThan(1000));
    final pdf = pw.Document();
    for (final name in ['株式会社テスト建設', '株式会社長い会社名建設工業']) {
      pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Genuine Reisho balanced layout / internal trial'),
            pw.SizedBox(height: 12),
            pw.Text(name, style: pw.TextStyle(font: font, fontSize: 14)),
            pw.SizedBox(height: 24),
            for (final size in [32.0, 42.0, 55.0]) ...[
              pw.Text('${size.toInt()} pt / glyph ${CompanySealPdf.reishoGlyphSize(name, size).toStringAsFixed(2)} pt'),
              pw.SizedBox(height: 8),
              CompanySealPdf.build(name, size: size, font: font,
                  style: CompanySealPdf.reishoStyle),
              pw.SizedBox(height: 24),
            ],
          ],
        ),
      ));
    }
    final output = Directory('build/company-seal-proof')..createSync(recursive: true);
    File('${output.path}/company_seal_reisho_balanced.pdf')
        .writeAsBytesSync(await pdf.save());
  });
}

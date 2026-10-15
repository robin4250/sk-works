import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real report PDF preserves portrait and landscape signed canvas', () async {
    final output = Directory(Platform.environment['SKO_SIGNATURE_PROOF']!)..createSync(recursive: true);
    final font = pw.Font.ttf(ByteData.sublistView(File('assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytesSync()));
    for (final entry in {'portrait': const Size(300, 600), 'landscape': const Size(900, 240)}.entries) {
      // Rectangle with a diagonal makes distorted proportions visible.
      final signature = {'strokes': SignatureResult(signerName: '署名確認', canvasSize: entry.value,
        strokes: [[const Offset(.1, .1), const Offset(.9, .1), const Offset(.9, .9), const Offset(.1, .9), const Offset(.1, .1), const Offset(.9, .9)]]).toJson()};
      final date = DateTime(2026, 10, 15);
      final report = DailyReportRecord(id: 'synthetic', siteId: 'site', siteName: '検証現場', date: date,
        workDescription: '署名縦横比検証', status: 'signed', workers: const [], signerName: '署名確認', signatureJson: signature);
      final bytes = await DailyReportPdfService.buildPdf(date: date, siteName: '検証現場', workers: const [],
        workDescription: '署名縦横比検証', report: report, regularFont: font, boldFont: font);
      File('${output.path}/${entry.key}.pdf').writeAsBytesSync(bytes);
    }
  }, skip: Platform.environment['SKO_SIGNATURE_PROOF'] == null ? 'Opt-in actual PDF proof.' : false);
}

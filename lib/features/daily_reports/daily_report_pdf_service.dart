import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'daily_report_repository.dart';

class DailyReportPdfService {
  const DailyReportPdfService._();

  static Future<Uint8List> buildPdf({
    required DateTime date,
    required String siteName,
    required List<DailyReportWorkerDraft> workers,
    required String workDescription,
    required DailyReportRecord? report,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '作 業 日 報',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 14),
            pw.Text('日付  ${date.year}/${date.month}/${date.day}'),
            pw.Text('現場  $siteName'),
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.Text(
              '出勤メンバー（${workers.length}名）',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            for (final worker in workers)
              pw.Text(
                '${worker.workerName}  残${_number(worker.overtimeHours)} '
                '早${_number(worker.earlyHours)} 夜${_number(worker.nightHours)} '
                '${worker.allowanceLabel}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.Text('作業内容', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(workDescription.isEmpty ? '（記載なし）' : workDescription),
            pw.Spacer(),
            if (report?.signed == true) ...[
              pw.Divider(),
              pw.Text(
                '責任者サイン済み：${report?.signerName ?? ''}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              if (report?.signedAt != null)
                pw.Text('確定日時：${report!.signedAt!.toLocal()}'),
            ],
          ],
        ),
      ),
    );
    return document.save();
  }

  static Future<bool> printReport({
    required DateTime date,
    required String siteName,
    required List<DailyReportWorkerDraft> workers,
    required String workDescription,
    required DailyReportRecord? report,
  }) {
    return Printing.layoutPdf(
      name: '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}_${siteName}_日報.pdf',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildPdf(
        date: date,
        siteName: siteName,
        workers: workers,
        workDescription: workDescription,
        report: report,
        format: format,
      ),
    );
  }

  static String buildTextSnapshot({
    required DateTime date,
    required String siteName,
    required List<DailyReportWorkerDraft> workers,
    required String workDescription,
    required DailyReportRecord? report,
  }) {
    final b = StringBuffer()
      ..writeln('作業日報')
      ..writeln('${date.year}/${date.month}/${date.day}')
      ..writeln(siteName)
      ..writeln(workDescription);
    for (final worker in workers) {
      b.writeln(worker.workerName);
    }
    if (report?.signed == true) {
      b.writeln('責任者サイン済み ${report?.signerName ?? ''}');
    }
    return b.toString();
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

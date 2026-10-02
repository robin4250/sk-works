// ignore_for_file: prefer_interpolation_to_compose_strings

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
        margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '作 業 日 報',
                    style: pw.TextStyle(
                      fontSize: 23,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
                pw.Text(
                  '${date.year}年 ${date.month}月 ${date.day}日',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.8),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  children: [
                    _cell('現場名\n$siteName', height: 52),
                    _cell(
                      '報告者\n${report?.reporterSignerName ?? ''}',
                      height: 52,
                    ),
                    _cell(
                      '責任者\n${report?.signerName ?? ''}',
                      height: 52,
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '作業内容',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Container(
              height: 150,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
              ),
              child: pw.Text(
                workDescription.isEmpty ? '（記載なし）' : workDescription,
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              '作業者名',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.8),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.0),
                1: pw.FlexColumnWidth(0.9),
                2: pw.FlexColumnWidth(0.9),
                3: pw.FlexColumnWidth(0.9),
                4: pw.FlexColumnWidth(1.6),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('氏名'),
                    _cell('早出'),
                    _cell('残業'),
                    _cell('夜間'),
                    _cell('手当・車両等'),
                  ],
                ),
                for (final worker in workers)
                  pw.TableRow(
                    children: [
                      _cell(worker.workerName),
                      _cell(worker.earlyHours > 0
                          ? _number(worker.earlyHours)
                          : ''),
                      _cell(worker.overtimeHours > 0
                          ? _number(worker.overtimeHours)
                          : ''),
                      _cell(worker.nightHours > 0
                          ? _number(worker.nightHours)
                          : ''),
                      _cell([
                        if (worker.allowanceLabel.trim().isNotEmpty)
                          worker.allowanceLabel,
                        if (worker.vehicleName?.trim().isNotEmpty == true)
                          '車両 ' + worker.vehicleName!,
                        if (worker.routeName?.trim().isNotEmpty == true)
                          'ルート ' + worker.routeName!,
                        if (worker.odometerKm != null)
                          '走行 ' + _number(worker.odometerKm!) + 'km',
                      ].join(' / ')),
                    ],
                  ),
              ],
            ),
            pw.Spacer(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _signatureBox(
                    label: '報告者サイン',
                    signerName: report?.reporterSignerName ?? '',
                    signatureJson: report?.reporterSignatureJson,
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: _signatureBox(
                    label: '責任者サイン',
                    signerName: report?.signerName ?? '',
                    signatureJson: report?.signatureJson,
                  ),
                ),
              ],
            ),
            if (report?.signedAt != null) ...[
              pw.SizedBox(height: 6),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '確定日時：${report!.signedAt!.toLocal()}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return document.save();
  }

  static pw.Widget _cell(String text, {double? height}) => pw.Container(
        height: height,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 9.5)),
      );

  static pw.Widget _signatureBox({
    required String label,
    required String signerName,
    required Object? signatureJson,
  }) {
    final svg = signatureSvg(signatureJson);
    return pw.Container(
      height: 92,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            '$label  $signerName',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 4),
          if (svg != null)
            pw.Expanded(child: pw.SvgImage(svg: svg))
          else
            pw.Expanded(
              child: pw.Center(
                child: pw.Text(
                  '未サイン',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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

  static String? signatureSvg(Object? value) {
    if (value is! List) return null;
    const width = 400.0;
    const height = 120.0;
    final elements = <String>[];

    for (final rawStroke in value) {
      if (rawStroke is! List || rawStroke.isEmpty) continue;
      final points = <String>[];
      for (final rawPoint in rawStroke) {
        if (rawPoint is! Map) continue;
        final rawX = rawPoint['x'];
        final rawY = rawPoint['y'];
        if (rawX is! num || rawY is! num) continue;
        final x = rawX.toDouble();
        final y = rawY.toDouble();
        final px = (x.clamp(0, 1) * width).toStringAsFixed(1);
        final py = (y.clamp(0, 1) * height).toStringAsFixed(1);
        points.add('$px,$py');
      }
      if (points.length >= 2) {
        elements.add(
          '<polyline points="${points.join(' ')}" '
          'fill="none" stroke="black" stroke-width="2.4" '
          'stroke-linecap="round" stroke-linejoin="round"/>',
        );
      } else if (points.length == 1) {
        final pair = points.single.split(',');
        elements.add(
          '<circle cx="${pair[0]}" cy="${pair[1]}" r="1.8" fill="black"/>',
        );
      }
    }

    if (elements.isEmpty) return null;
    return '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 ${width.toInt()} ${height.toInt()}">'
        '${elements.join()}'
        '</svg>';
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
      b.writeln([
        worker.workerName,
        if (worker.vehicleName?.trim().isNotEmpty == true)
          '車両 ' + worker.vehicleName!,
        if (worker.routeName?.trim().isNotEmpty == true)
          'ルート ' + worker.routeName!,
        if (worker.odometerKm != null)
          '走行 ' + _number(worker.odometerKm!) + 'km',
      ].join(' / '));
    }
    if (report?.reporterSignatureJson != null) {
      b.writeln('報告者サイン済み ${report?.reporterSignerName ?? ''}');
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

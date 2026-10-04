// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../international/language_controller.dart';
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

    final totalOvertime =
        workers.fold<double>(0, (sum, worker) => sum + worker.overtimeHours);
    final totalEarly =
        workers.fold<double>(0, (sum, worker) => sum + worker.earlyHours);
    final totalNight =
        workers.fold<double>(0, (sum, worker) => sum + worker.nightHours);
    final allowanceCounts = <String, int>{};
    for (final worker in workers) {
      final label = worker.allowanceLabel.trim();
      if (label.isEmpty) continue;
      allowanceCounts[label] = (allowanceCounts[label] ?? 0) + 1;
    }
    final summaryItems = <MapEntry<String, String>>[
      MapEntry(SkoLanguageController.tr('計'), SkoLanguageController.isEnglish ? '${workers.length} workers' : '${workers.length}人工'),
      if (totalEarly > 0) MapEntry(SkoLanguageController.tr('早出'), '${_number(totalEarly)}H'),
      if (totalOvertime > 0) MapEntry(SkoLanguageController.tr('残業'), '${_number(totalOvertime)}H'),
      if (totalNight > 0) MapEntry(SkoLanguageController.tr('夜間'), '${_number(totalNight)}H'),
      for (final entry in allowanceCounts.entries)
        MapEntry(entry.key, entry.value.toString()),
    ];

    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    SkoLanguageController.isEnglish ? 'DAILY WORK REPORT' : '作業日報',
                    style: pw.TextStyle(
                      fontSize: 25,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Text(
                  '${date.year}年 ${date.month}月 ${date.day}日',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: _boxed(
                    SkoLanguageController.tr('現場名'),
                    pw.Text(
                      siteName.isEmpty ? SkoLanguageController.tr('未登録') : siteName,
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    height: 78,
                  ),
                ),
                pw.SizedBox(width: 5),
                pw.Expanded(
                  flex: 3,
                  child: _signatureBox(
                    SkoLanguageController.tr('報告者サイン'),
                    report?.reporterSignerName ?? '',
                    report?.reporterSignatureJson,
                  ),
                ),
                pw.SizedBox(width: 5),
                pw.Expanded(
                  flex: 3,
                  child: _signatureBox(
                    SkoLanguageController.tr('責任者サイン'),
                    report?.responsibleSignerName ?? report?.signerName ?? '',
                    report?.responsibleSignatureJson ?? report?.signatureJson,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 7),
            pw.Row(
              children: [
                pw.Expanded(
                  child: _summaryBox(
                    SkoLanguageController.tr('日付'),
                    '${date.year}年${date.month}月${date.day}日',
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: _summaryBox(
                    SkoLanguageController.tr('現場'),
                    siteName.isEmpty ? SkoLanguageController.tr('未登録') : siteName,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 7),
            _boxed(
              SkoLanguageController.tr('作業内容'),
              pw.Text(
                workDescription.trim().isEmpty ? SkoLanguageController.tr('（記載なし）') : workDescription,
                style: const pw.TextStyle(fontSize: 11),
              ),
              height: 150,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              SkoLanguageController.isEnglish ? 'WORKERS' : '作 業 者 名',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: [for (final label in ['氏名', '早出', '残業', '夜間', '手当・車両等']) SkoLanguageController.tr(label)],
              data: [
                for (final worker in workers)
                  [
                    worker.workerName,
                    worker.earlyHours > 0 ? _number(worker.earlyHours) : '',
                    worker.overtimeHours > 0
                        ? _number(worker.overtimeHours)
                        : '',
                    worker.nightHours > 0 ? _number(worker.nightHours) : '',
                    [
                      if (worker.allowanceLabel.trim().isNotEmpty)
                        worker.allowanceLabel,
                      if (worker.vehicleName?.trim().isNotEmpty == true)
                        worker.vehicleName!,
                      if (worker.routeName?.trim().isNotEmpty == true)
                        worker.routeName!,
                    ].join(' / '),
                  ],
                for (var i = workers.length; i < 9; i++)
                  const ['', '', '', '', ''],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey100),
              border: pw.TableBorder.all(width: 0.7),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(0.9),
                2: pw.FlexColumnWidth(0.9),
                3: pw.FlexColumnWidth(0.9),
                4: pw.FlexColumnWidth(2.2),
              },
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                for (var index = 0; index < summaryItems.length; index++) ...[
                  if (index > 0) pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: _summaryBox(
                      summaryItems[index].key,
                      summaryItems[index].value,
                    ),
                  ),
                ],
              ],
            ),
            pw.Spacer(),
            pw.Divider(thickness: 0.8),
            pw.Text(
              SkoLanguageController.tr('出勤時の写真・位置情報はSKOアプリ内の日報から確認できます。'),
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
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

  static pw.Widget _boxed(
    String label,
    pw.Widget child, {
    double? height,
  }) {
    return pw.Container(
      height: height,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Expanded(child: child),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox(
    String label,
    String name,
    Object? signatureJson,
  ) {
    final svg = signatureSvg(signatureJson);
    return pw.Container(
      height: 78,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (name.trim().isNotEmpty)
            pw.Text(
              name.trim(),
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 7.5),
            ),
          pw.SizedBox(height: 2),
          if (svg != null)
            pw.Expanded(child: pw.SvgImage(svg: svg))
          else
            pw.Spacer(),
        ],
      ),
    );
  }

  static pw.Widget _summaryBox(String label, String value) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8),
        ),
        child: pw.Row(
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Spacer(),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

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
      ..writeln(SkoLanguageController.tr('作業日報'))
      ..writeln('${date.year}/${date.month}/${date.day}')
      ..writeln(siteName)
      ..writeln(workDescription);
    for (final worker in workers) {
      b.writeln([
        worker.workerName,
        if (worker.vehicleName?.trim().isNotEmpty == true)
          SkoLanguageController.tr('車両') + ' ' + worker.vehicleName!,
        if (worker.routeName?.trim().isNotEmpty == true)
          SkoLanguageController.tr('ルート') + ' ' + worker.routeName!,
        if (worker.odometerKm != null)
          SkoLanguageController.tr('走行') + ' ' + _number(worker.odometerKm!) + 'km',
      ].join(' / '));
    }
    if (report?.reporterSignatureJson != null) {
      b.writeln('${SkoLanguageController.tr('報告者サイン済み')} ${report?.reporterSignerName ?? ''}');
    }
    if (report?.signed == true) {
      b.writeln('${SkoLanguageController.tr('責任者サイン済み')} ${report?.signerName ?? ''}');
    }
    return b.toString();
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

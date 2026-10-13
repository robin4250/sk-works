import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../international/language_controller.dart';
import 'package:printing/printing.dart';

import 'worker_attendance_sheet_repository.dart';

class AttendancePdfService {
  const AttendancePdfService._();

  static Future<Uint8List> buildPdf(
    DateTime month,
    WorkerAttendanceMonth data, {
    PdfPageFormat format = PdfPageFormat.a4,
    String? workerName,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final rows = data.days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
        build: (_) => [
          pw.Text(
            [
              '出勤表',
              if (workerName?.trim().isNotEmpty == true) workerName!.trim(),
              '${month.year}年${month.month}月',
            ].join('  '),
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(_summaryText(data)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [for (final label in ['日付', '現場', '出勤', '退勤', '残業', '早出', '夜間', '手当']) SkoLanguageController.tr(label)],
            data: [
              for (final day in rows)
                [
                  '${day.date.month}/${day.date.day}',
                  day.paidLeave
                      ? SkoLanguageController.tr('有給')
                      : day.worked
                          ? (day.siteName ?? SkoLanguageController.tr('現場'))
                          : SkoLanguageController.tr('休み'),
                  _time(day.clockIn),
                  _time(day.clockOut),
                  _hoursCell(day.overtimeHours),
                  _hoursCell(day.earlyHours),
                  _hoursCell(day.nightHours),
                  day.hasAllowance
                      ? (day.allowanceNames.isEmpty
                          ? (SkoLanguageController.isEnglish ? 'Allowance 1 time' : '手当1回')
                          : day.allowanceNames
                              .map(
                                (name) =>
                                    '${name}1${day.allowanceUnits[name] ?? '回'}',
                              )
                              .join(' '))
                      : '',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<bool> printMonth(
    DateTime month,
    WorkerAttendanceMonth data, {
    String? workerName,
  }) {
    return Printing.layoutPdf(
      name: '${month.year}年${month.month}月_${workerName?.trim().isNotEmpty == true ? '${workerName!.trim()}_' : ''}出勤表.pdf',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildPdf(
        month,
        data,
        format: format,
        workerName: workerName,
      ),
    );
  }

  static Future<bool> printWorkers(
    DateTime month,
    List<({String workerName, WorkerAttendanceMonth data})> workers,
  ) {
    return Printing.layoutPdf(
      name: '${month.year}年${month.month}月_出勤表一覧.pdf',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildWorkersPdf(month, workers, format: format),
    );
  }

  static Future<Uint8List> buildWorkersPdf(
    DateTime month,
    List<({String workerName, WorkerAttendanceMonth data})> workers, {
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    for (final worker in workers) {
      final rows = worker.data.days.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      document.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(14 * PdfPageFormat.mm),
          build: (_) => [
            pw.Text(
              '出勤表  ${worker.workerName}  ${month.year}年${month.month}月',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(_summaryText(worker.data)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: [
                for (final label
                    in ['日付', '現場', '出勤', '退勤', '残業', '早出', '夜間', '手当'])
                  SkoLanguageController.tr(label),
              ],
              data: [
                for (final day in rows)
                  [
                    '${day.date.month}/${day.date.day}',
                    day.paidLeave
                        ? SkoLanguageController.tr('有給')
                        : day.worked
                            ? (day.siteName ?? SkoLanguageController.tr('現場'))
                            : SkoLanguageController.tr('休み'),
                    _time(day.clockIn),
                    _time(day.clockOut),
                    _hoursCell(day.overtimeHours),
                    _hoursCell(day.earlyHours),
                    _hoursCell(day.nightHours),
                    day.hasAllowance
                        ? (day.allowanceNames.isEmpty
                            ? '手当1回'
                            : day.allowanceNames
                                .map(
                                  (name) =>
                                      '${name}1${day.allowanceUnits[name] ?? '回'}',
                                )
                                .join(' '))
                        : '',
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 8.5),
              cellPadding: const pw.EdgeInsets.all(4),
            ),
          ],
        ),
      );
    }
    return document.save();
  }

  static String buildTextSnapshot(DateTime month, WorkerAttendanceMonth data) {
    final rows = data.days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final b = StringBuffer()
      ..writeln(SkoLanguageController.isEnglish ? 'Attendance ${month.month}/${month.year}' : '出勤表 ${month.year}年${month.month}月')
      ..writeln(SkoLanguageController.isEnglish ? 'Attendance ${data.workedDays} days' : '出勤 ${data.workedDays}日');
    for (final day in rows) {
      b.writeln(
        '${day.date.month}/${day.date.day} '
        "${day.paidLeave ? SkoLanguageController.tr('有給') : day.worked ? (day.siteName ?? SkoLanguageController.tr('現場')) : SkoLanguageController.tr('休み')} "
        '${_time(day.clockIn)}-${_time(day.clockOut)}',
      );
    }
    return b.toString();
  }

  static String _time(DateTime? value) {
    if (value == null) return '--:--';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  static String _summaryText(WorkerAttendanceMonth data) {
    final parts = <String>[
      if (data.workedDays > 0)
        SkoLanguageController.isEnglish
            ? 'Attendance ${data.workedDays} days'
            : '出勤 ${data.workedDays}日',
      if (data.overtimeHours > 0)
        SkoLanguageController.isEnglish
            ? 'Overtime ${_number(data.overtimeHours)} hours'
            : '残業 ${_number(data.overtimeHours)}時間',
      if (data.earlyHours > 0)
        SkoLanguageController.isEnglish
            ? 'Early ${_number(data.earlyHours)} hours'
            : '早出 ${_number(data.earlyHours)}時間',
      if (data.nightHours > 0)
        SkoLanguageController.isEnglish
            ? 'Night ${_number(data.nightHours)} hours'
            : '夜間 ${_number(data.nightHours)}時間',
      for (final entry in data.allowanceCounts.entries)
        if (entry.value > 0)
          '${entry.key} ${entry.value}${data.allowanceUnits[entry.key] ?? '回'}',
    ];
    return parts.isEmpty ? SkoLanguageController.tr('集計なし') : parts.join(' / ');
  }

  static String _hoursCell(double value) =>
      value > 0 ? _number(value) : '';

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

}

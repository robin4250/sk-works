import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'worker_attendance_sheet_repository.dart';

class AttendancePdfService {
  const AttendancePdfService._();

  static Future<Uint8List> buildPdf(
    DateTime month,
    WorkerAttendanceMonth data, {
    PdfPageFormat format = PdfPageFormat.a4,
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
            '出勤表  ${month.year}年${month.month}月',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(_summaryText(data)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['日付', '現場', '出勤', '退勤', '残業', '早出', '夜間', '手当'],
            data: [
              for (final day in rows)
                [
                  '${day.date.month}/${day.date.day}',
                  day.worked ? (day.siteName ?? '現場') : '休み',
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
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<bool> printMonth(DateTime month, WorkerAttendanceMonth data) {
    return Printing.layoutPdf(
      name: '${month.year}年${month.month}月_出勤表.pdf',
      format: PdfPageFormat.a4,
      onLayout: (format) => buildPdf(month, data, format: format),
    );
  }

  static String buildTextSnapshot(DateTime month, WorkerAttendanceMonth data) {
    final rows = data.days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final b = StringBuffer()
      ..writeln('出勤表 ${month.year}年${month.month}月')
      ..writeln('出勤 ${data.workedDays}日');
    for (final day in rows) {
      b.writeln(
        '${day.date.month}/${day.date.day} '
        "${day.worked ? (day.siteName ?? '現場') : '休み'} "
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
      if (data.workedDays > 0) '出勤 ${data.workedDays}日',
      if (data.overtimeHours > 0) '残業 ${_number(data.overtimeHours)}時間',
      if (data.earlyHours > 0) '早出 ${_number(data.earlyHours)}時間',
      if (data.nightHours > 0) '夜間 ${_number(data.nightHours)}時間',
      for (final entry in data.allowanceCounts.entries)
        if (entry.value > 0)
          '${entry.key} ${entry.value}${data.allowanceUnits[entry.key] ?? '回'}',
    ];
    return parts.isEmpty ? '集計なし' : parts.join(' / ');
  }

  static String _hoursCell(double value) =>
      value > 0 ? _number(value) : '';

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

}

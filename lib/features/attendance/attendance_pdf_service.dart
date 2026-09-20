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
          pw.Text(
            '出勤 ${data.workedDays}日 / 残業 ${_number(data.overtimeHours)}時間 / '
            '早出 ${_number(data.earlyHours)}時間 / 夜間 ${_number(data.nightHours)}時間'
            "${data.allowanceYen > 0 ? ' / 手当 ${_yen(data.allowanceYen)}' : ''}",
          ),
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
                  _number(day.overtimeHours),
                  _number(day.earlyHours),
                  _number(day.nightHours),
                  day.allowanceYen == 0 ? '' : _yen(day.allowanceYen),
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

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _yen(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return '${negative ? '-' : ''}¥$out';
  }
}

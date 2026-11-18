import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../attendance/attendance_pdf_service.dart';
import '../attendance/worker_attendance_sheet_repository.dart';
import '../payroll/payroll_statement_repository.dart';
import 'own_payroll_archive_pdf.dart';

/// Converts trusted retirement source snapshots using SKO's document layouts.
class RetirementPdfRenderer {
  const RetirementPdfRenderer({
    required this.regularFont,
    required this.boldFont,
  });

  final pw.Font regularFont;
  final pw.Font boldFont;

  Future<Uint8List> payroll(
    Map<String, Object?> snapshot, {
    required String verifiedPersonId,
    required String snapshotPersonId,
    required String companyId,
  }) {
    if (snapshot['hasAdditionalAdjustments'] != false) {
      throw const FormatException('追加内訳を含む給与明細を確認できません。');
    }
    if (snapshot['legacyFinalized'] == true) {
      if (verifiedPersonId.isEmpty || verifiedPersonId != snapshotPersonId ||
          companyId.isEmpty) {
        throw const FormatException('本人の確定済み明細を確認できません。');
      }
      return _legacyPayroll(snapshot);
    }
    final totals = snapshot['result'] as Map;
    final record = PayrollStatementRecord(
      id: snapshot['sourceId'] as String,
      revision: int.parse(snapshot['revision'] as String),
      workflowState: 'finalized',
      companyName: snapshot['companyName'] as String,
      workerName: snapshot['workerName'] as String,
      periodStart: DateTime.parse(snapshot['periodStart'] as String),
      periodEnd: DateTime.parse(snapshot['periodEnd'] as String),
      issuedAt: DateTime.tryParse(snapshot['issuedAt'] as String? ?? ''),
      grossPay: totals['gross_pay'] as int,
      deductions: totals['deductions'] as int,
      netPay: totals['net_pay'] as int,
      detail: Map<String, dynamic>.from(snapshot['detail'] as Map),
    );
    return OwnPayrollArchivePdf.build(
      source: record,
      verifiedPersonId: verifiedPersonId,
      snapshotPersonId: snapshotPersonId,
      sourceCompanyId: companyId,
      regularFont: regularFont,
      boldFont: boldFont,
    );
  }

  Future<Uint8List> _legacyPayroll(Map<String, Object?> snapshot) {
    final totals = snapshot['result'] as Map;
    final detail = OwnPayrollArchivePdf.projectNumericDetail(
      Map<String, dynamic>.from(snapshot['detail'] as Map),
    );
    final rows = [
      for (final entry in detail.entries)
        if (entry.value is num) [entry.key, entry.value.toString()],
    ];
    final from = DateTime.parse(snapshot['periodStart'] as String);
    final through = DateTime.parse(snapshot['periodEnd'] as String);
    String day(DateTime date) => '${date.year}/${date.month}/${date.day}';
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(level: 0, text: '給与明細'),
        pw.Text(snapshot['companyName'] as String),
        pw.Text(snapshot['workerName'] as String),
        pw.Text('${day(from)} ～ ${day(through)}'),
        if (snapshot['issuedAt'] case final String issued)
          pw.Text('発行日 ${day(DateTime.parse(issued))}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['保存済み合計', '金額'],
          data: [
            ['総支給額', '${totals['gross_pay'] as int} 円'],
            ['総控除額', '${totals['deductions'] as int} 円'],
            ['差引支給額', '${totals['net_pay'] as int} 円'],
          ],
        ),
        pw.SizedBox(height: 16),
        if (rows.isEmpty) pw.Text('この明細には項目別の内訳が保存されていません。')
        else pw.TableHelper.fromTextArray(headers: ['保存済み内訳', '記録値'], data: rows),
      ],
    ));
    return document.save();
  }

  Future<Uint8List> attendance(
    WorkerAttendanceMonth source, {
    required String workerName,
    required DateTime cutoff,
  }) {
    if (source.pendingDetailsUnavailable ||
        source.days.values.any((day) =>
          day.date.year != source.year ||
          day.date.month != source.month ||
          day.date.isAfter(cutoff) ||
          day.pendingReports.isNotEmpty)) {
      throw const FormatException('確定済みの本人出勤表を確認できません。');
    }
    return AttendancePdfService.buildPdf(
      DateTime(source.year, source.month),
      source,
      workerName: workerName,
      regularFont: regularFont,
      boldFont: boldFont,
    );
  }
}

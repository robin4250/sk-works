import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../expenses/expense_claim.dart';
import '../expenses/expense_detail_pdf.dart';
import '../expenses/expense_document_repository.dart';
import '../payroll/payroll_pdf_service.dart';
import '../payroll/payroll_statement_repository.dart';

/// Candidate renderer adapter, not authentication. The server must verify the
/// owner and freeze the original own-record before invoking this adapter.
class OwnPayrollArchivePdf {
  const OwnPayrollArchivePdf._();

  static Map<String, dynamic> projectNumericDetail(Map<String, dynamic> source) {
    const keys = ['基本給', '残業手当', '交通費', '出勤に基づく支給額', '健康保険料',
      '介護保険料', '厚生年金保険', '雇用保険料', '子ども・子育て支援金', '所得税',
      '住民税', '道具代', '社会保険', '出勤日数', '休出日数', '残業時間', '早出時間',
      '夜間時間', '有給日数'];
    final result = <String, dynamic>{'company_seal_enabled': false};
    for (final key in keys) {
      final value = source[key];
      if (value is num && value.isFinite) result[key] = value;
    }
    return result;
  }

  static Future<Uint8List> build({
    required PayrollStatementRecord source,
    required String verifiedPersonId,
    required String snapshotPersonId,
    required String sourceCompanyId,
    required pw.Font regularFont,
    required pw.Font boldFont,
  }) {
    if (verifiedPersonId.isEmpty || verifiedPersonId != snapshotPersonId ||
        sourceCompanyId.isEmpty || source.workflowState != 'finalized' ||
        source.revision == null || source.revision! < 0) {
      throw StateError('本人の確定済み明細を確認できません。');
    }
    for (final key in ['custom_earnings', 'custom_deductions']) {
      final entries = source.detail[key];
      if (entries != null && (entries is! List || entries.isNotEmpty)) {
        throw StateError('本人PDFの追加内訳は未対応です。');
      }
    }
    final detail = projectNumericDetail(source.detail);
    const earnings = ['基本給', '残業手当', '交通費', '出勤に基づく支給額'];
    const deductions = ['健康保険料', '介護保険料', '厚生年金保険', '雇用保険料',
      '子ども・子育て支援金', '所得税', '住民税', '道具代', '社会保険'];
    num sum(List<String> keys) => keys.fold<num>(0,
      (total, key) => total + ((detail[key] as num?) ?? 0));
    if (sum(earnings) != source.grossPay || sum(deductions) != source.deductions ||
        source.grossPay - source.deductions != source.netPay) {
      throw StateError('本人PDFの全支給・控除内訳を確認できません。');
    }
    final projected = PayrollStatementRecord(id: source.id,
      companyName: source.companyName, workerName: source.workerName,
      periodStart: source.periodStart, periodEnd: source.periodEnd,
      grossPay: source.grossPay, deductions: source.deductions, netPay: source.netPay,
      detail: detail, issuedAt: source.issuedAt,
      workflowState: source.workflowState, revision: source.revision);
    // Explicit empty expense details prevents the original renderer from
    // implicitly loading expense data through Supabase during archive export.
    return PayrollPdfService.buildPdf(projected,
      regularFont: regularFont, boldFont: boldFont,
      expenseDetails: ExpenseDocumentDetails(kind: ExpenseDocument.payroll,
        documentId: source.id, subjectId: verifiedPersonId, month: source.periodStart,
        claims: ExpenseClaims(companyId: sourceCompanyId, claims: const [])));
  }
}

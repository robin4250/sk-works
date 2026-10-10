import '../../data/supabase_backend.dart';
import 'expense_claim.dart';
import 'expense_detail_pdf.dart';

class ExpenseDocumentDetails {
  ExpenseDocumentDetails({
    required this.kind,
    required this.documentId,
    required this.subjectId,
    required this.month,
    required this.claims,
  });
  final ExpenseDocument kind;
  final String documentId, subjectId;
  final DateTime month;
  final ExpenseClaims claims;
  factory ExpenseDocumentDetails.parse(
    Map<String, dynamic> v,
    ExpenseDocument kind,
    String documentId,
    DateTime month, {
    int? revision,
    String? updatedAt,
  }) {
    final date = DateTime.parse(v['month']);
    if (v['kind'] != kind.name ||
        v['document_id'] != documentId ||
        date.year != month.year ||
        date.month != month.month ||
        (revision != null && v['revision'] != revision) ||
        (updatedAt != null &&
            DateTime.tryParse(v['updated_at']?.toString() ?? '') !=
                DateTime.tryParse(updatedAt))) {
      throw StateError('帳票の版・利用月が変わりました。再読み込みしてください。');
    }
    final company = v['company_id'] as String,
        subject = v['subject_id'] as String;
    final entries = (v['claims'] as List).map((raw) {
      final r = Map<String, dynamic>.from(raw);
      final incurred = DateTime.parse(r['incurred_on']);
      final c = ExpenseClaim(
        id: r['id'],
        companyId: r['company_id'],
        applicantId: r['applicant_id'],
        applicantName: r['applicant_name'],
        incurredOn: incurred,
        submittedAt: DateTime.parse(r['submitted_at']),
        description: r['description'],
        amountYen: r['amount_yen'],
        approval: ExpenseApproval.values.byName(r['approval']),
        revision: r['revision'] as int? ?? 1,
        withdrawn: r['withdrawn'] == true,
        allocation: ExpenseAllocation(
          ExpenseCategory.values.byName(r['allocation']),
          counterpartyId: r['counterparty_id'],
          counterpartyName: r['counterparty_name'],
        ),
      );
      if (c.companyId != company ||
          incurred.year != month.year ||
          incurred.month != month.month ||
          (kind == ExpenseDocument.payroll
              ? c.applicantId != subject
              : c.allocation.counterpartyId != subject ||
                    c.allocation.category !=
                        (kind == ExpenseDocument.invoice
                            ? ExpenseCategory.customer
                            : ExpenseCategory.subcontractor))) {
        throw StateError('経費明細の対象が一致しません。');
      }
      return c;
    });
    return ExpenseDocumentDetails(
      kind: kind,
      documentId: documentId,
      subjectId: subject,
      month: date,
      claims: ExpenseClaims(companyId: company, claims: entries),
    );
  }
}

class ExpenseDocumentRepository {
  static Future<ExpenseDocumentDetails?> load(
    ExpenseDocument kind,
    String id,
    DateTime month, {
    int? revision,
    String? updatedAt,
  }) async {
    // Local previews have no saved document; never match by a display name.
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        !SupabaseBackend.isInitialized) {
      return null;
    }
    final client = SupabaseBackend.client,
        actor = SupabaseBackend.client.auth.currentUser?.id;
    if (actor == null) throw StateError('ログインが必要です。');
    final raw = await client.rpc(
      'read_expense_document',
      params: {'p_kind': kind.name, 'p_document': id},
    );
    if (client.auth.currentUser?.id != actor) {
      throw StateError('ログイン情報が変わりました。');
    }
    return ExpenseDocumentDetails.parse(
      Map<String, dynamic>.from(raw),
      kind,
      id,
      month,
      revision: revision,
      updatedAt: updatedAt,
    );
  }
}

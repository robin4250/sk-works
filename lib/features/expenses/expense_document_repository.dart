import '../../domain/expense_cost_direction_v2_candidate.dart';
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
    this.costRecoveryAmountYen,
    this.directionalCost,
  });
  final ExpenseDocument kind;
  final String documentId, subjectId;
  final DateTime month;
  final ExpenseClaims claims;
  final int? costRecoveryAmountYen;
  final ExpenseCostDirectionV2Candidate? directionalCost;
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
    final costAmount = v['cost_recovery_amount_yen'];
    if (costAmount != null && (kind == ExpenseDocument.payroll ||
        costAmount is! int || costAmount < 0)) {
      throw StateError('別途経費の帳票金額を確認できません。');
    }
    ExpenseCostDirectionV2Candidate? directional;
    if (v.containsKey('expense_cost_direction_v2')) {
      if (kind != ExpenseDocument.paymentCertificate || v['revision'] is! int || v['document_id'] != documentId) {
        throw StateError('方向付き経費の帳票対象を確認できません。');
      }
      directional = ExpenseCostDirectionV2Candidate.parse(v['expense_cost_direction_v2'], expected: ExpenseCostContext(
        kind: ExpenseCostDocumentKind.paymentCertificate, companyId: company, documentId: documentId,
        subjectId: subject, month: '${date.year}-${date.month.toString().padLeft(2, '0')}', documentRevision: v['revision'] as int));
      directional.verifyDetails({...directional.fields, 'claims': entries.map((claim) => {
        'id': claim.id, 'revision': claim.revision, 'amount_yen': claim.amountYen,
      }).toList()});
      if (costAmount != directional.amountYen) throw StateError('方向付き経費の原額が一致しません。');
    }
    return ExpenseDocumentDetails(
      kind: kind,
      documentId: documentId,
      subjectId: subject,
      month: date,
      claims: ExpenseClaims(companyId: company, claims: entries),
      costRecoveryAmountYen: costAmount as int?,
      directionalCost: directional,
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

import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/secondary_reset_session_guard.dart';
import '../shared/trade_document_form_session.dart';

/// Read-only evidence bound to the displayed company and one captured live SDK session.
class ScopedRequiredDocumentAttentionRepository {
  ScopedRequiredDocumentAttentionRepository(this.client);
  final SupabaseClient client;

  Future<Map<String, dynamic>> load({String? companyId, String? Function()? currentCompany}) async {
    final captured = client.auth.currentSession;
    final identity = SecondaryResetSessionGuard.identityOf(captured);
    if (identity == null) { throw StateError('ログイン状態を確認してください。'); }
    final lease = TradeDocumentFormSession(client,
      target: companyId, currentTarget: companyId == null ? null : (currentCompany ?? () => companyId));
    try {
      await lease.ready();
      final members = await lease.readOwnMemberships();
      if (members is! List || members.any((row) => row is! Map)) {
        throw StateError('会社を確認できません。');
      }
      final matching = members.whereType<Map>().where((row) =>
        companyId == null || row['company_id'] == companyId).toList();
      // No implicit first company. A caller without an explicit company needs
      // exactly one membership; ambiguity is unknown, never an empty obligation.
      if (matching.length != 1 || (companyId == null && members.length != 1)) {
        throw StateError('対象の会社を選択して開き直してください。');
      }
      final company = matching.single['company_id'];
      if (company is! String || company.isEmpty) { throw StateError('会社を確認できません。'); }
      final raw = await lease.rpc('current_user_required_document_attention_for_company', {'p_company_id': company});
      lease.requireScope();
      if (raw is! Map || raw['capability_version'] != 1 || raw['company_id'] != company ||
          '${raw['actor_id']}/${raw['session_id']}' != identity ||
          raw['worker_id'] is! String || (raw['worker_id'] as String).isEmpty ||
          raw['missing_names'] is! List || raw['unknown_names'] is! List) {
        throw StateError('書類の確認結果を照合できません。');
      }
      return Map<String, dynamic>.from(raw);
    } finally { lease.dispose(); }
  }
}

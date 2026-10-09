import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'payment_certificate_repository.dart';
import 'site_payment_agreement_document.dart';

class ConfirmedSitePayment {
  const ConfirmedSitePayment({required this.companyId, required this.proposalId,
    required this.siteName, required this.counterpartyName, required this.revision});
  final String companyId;
  final String proposalId;
  final String siteName;
  final String counterpartyName;
  final int revision;

  static Map<String, dynamic>? latestConfirmed(Map<String, dynamic> workspace) {
    final raw = workspace['proposals'];
    if (raw is! List || raw.isEmpty) return null;
    final proposals = raw.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList();
    if (proposals.isEmpty || proposals.any((p) => p['revision'] is! int)) return null;
    proposals.sort((a, b) => (b['revision'] as int).compareTo(a['revision'] as int));
    final latest = proposals.first;
    final parent = workspace['parent_company_id'];
    final child = workspace['child_company_id'];
    if (parent is! String || child is! String || parent == child) return null;
    final confirmations = latest['confirmations'];
    if (confirmations is! List) return null;
    final companies = confirmations.whereType<Map>().map((c) => c['company_id']).toSet();
    return companies.contains(parent) && companies.contains(child) ? latest : null;
  }
}

/// Reads shared proposals independently of legacy monthly certificates.
/// Snapshot creation happens only after the user explicitly opens a document.
class SitePaymentCertificatesRepository {
  SitePaymentCertificatesRepository(this._client);
  final SupabaseClient _client;

  static SitePaymentCertificatesRepository? maybeCreate() =>
      SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null
          ? SitePaymentCertificatesRepository(SupabaseBackend.client) : null;

  Future<List<ConfirmedSitePayment>> load(String company) async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final memberships = await _client.from('company_members').select('role')
        .eq('user_id', user.id).eq('company_id', company);
    if (!memberships.any((row) => row['role'] == 'owner' || row['role'] == 'admin')) {
      return const [];
    }
    final result = <ConfirmedSitePayment>[];
      try {
        final targets = await _client.rpc('site_payment_agreement_targets', params: {'p_company': company});
        if (targets is! List) throw StateError('共有現場の取得結果を確認できません。');
        for (final target in targets.whereType<Map>()) {
          final raw = await _client.rpc('site_payment_agreement_workspace',
              params: {'p_item': target['shared_item_id'], 'p_company': company});
          if (raw is! Map) throw StateError('現場別合意の取得結果を確認できません。');
          if (raw['parent_company_id'] != company && raw['child_company_id'] != company) {
            throw StateError('合意帳票の会社を確認できません。');
          }
          final latest = ConfirmedSitePayment.latestConfirmed(Map<String, dynamic>.from(raw));
          if (latest == null) continue;
          final id = latest['id'];
          if (id is! String || id.isEmpty) throw StateError('合意IDを確認できません。');
          result.add(ConfirmedSitePayment(companyId: company, proposalId: id,
              siteName: target['site_name'].toString(),
              counterpartyName: target['counterparty_name'].toString(),
              revision: latest['revision'] as int));
        }
      } on PostgrestException catch (e) {
        // Deployment gates remain server-owned. Other errors remain visible.
        if (!{'42883', 'PGRST202', '55000'}.contains(e.code)) {
          rethrow;
        }
        return const [];
      }
    return result;
  }

  Future<PaymentCertificateRecord> open(ConfirmedSitePayment item) async {
    final raw = await _client.rpc('saved_site_payment_document',
        params: {'p_proposal': item.proposalId, 'p_company': item.companyId});
    if (raw is! Map) {
      throw StateError('保存された合意帳票を確認できません。');
    }
    if (raw['proposal_id'] != item.proposalId || raw['revision'] != item.revision ||
        (raw['parent_company_id'] != item.companyId && raw['subcontractor_company_id'] != item.companyId)) {
      throw StateError('合意帳票の対象を確認できません。');
    }
    return SitePaymentAgreementDocument.fromSnapshot(Map<String, dynamic>.from(raw));
  }
}

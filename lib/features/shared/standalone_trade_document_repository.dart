import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import '../../domain/company_seal_snapshot.dart';
import '../../domain/partner_company_bank_account.dart';

/// Read-only registration context. No financial rows, contract saves or uploads.
class StandaloneTradeDocumentRepository {
  StandaloneTradeDocumentRepository(this._client) : _actor = _client.auth.currentUser?.id,
      _token = _client.auth.currentSession?.accessToken {
    _auth = _client.auth.onAuthStateChange.listen((_) {
      if (!_same) invalidate();
    }, onError: (_) => invalidate(), onDone: invalidate);
  }
  static StandaloneTradeDocumentRepository? maybeCreate() => SupabaseBackend.isInitialized &&
    SupabaseBackend.client.auth.currentSession != null ? StandaloneTradeDocumentRepository(SupabaseBackend.client) : null;
  final SupabaseClient _client;
  final String? _actor, _token;
  StreamSubscription<dynamic>? _auth;
  bool _revoked = false;
  Future<void>? _disposing;
  bool get _same => !_revoked && _actor != null && _token != null &&
    _client.auth.currentUser?.id == _actor && _client.auth.currentSession?.accessToken == _token &&
    _client.auth.currentSession?.isExpired == false;
  void invalidate() { _revoked = true; }
  void verify() { if (!_same) { invalidate(); throw StateError('ログイン状態が変わりました。会社詳細から開き直してください。'); } }
  Future<Object?> _rpc(String action, Map<String, dynamic> params) async {
    verify();
    final raw = await _client.rpc(action, params: params).setHeader('Authorization', 'Bearer $_token');
    verify(); return raw;
  }
  Future<Map<String, dynamic>> load({required String tradeCompanyId, required bool acceptance}) async {
    verify();
    final memberships = await _client.from('company_members').select('company_id,role')
      .eq('user_id', _actor!).setHeader('Authorization', 'Bearer $_token');
    verify();
    if (memberships.length != 1 || !const {'owner', 'admin'}.contains(memberships.single['role'])) {
      throw StateError('会社を一意に確認できる管理者として開いてください。');
    }
    final companyId = memberships.single['company_id'].toString();
    final raw = await _rpc('trade_company_contact_workspace', {});
    if (raw is! List) throw StateError('登録会社を確認できません。');
    final matches = raw.whereType<Map>().where((v) => v['id'] == tradeCompanyId).toList();
    if (matches.length != 1 || !(acceptance ? const {'customer', 'both'} : const {'subcontractor', 'both'}).contains(matches.single['trade_role'])) {
      throw StateError('選択した登録会社を確認できません。');
    }
    final partner = Map<String, dynamic>.from(matches.single);
    final profileRaw = await _rpc('read_partner_company_profile', {'p_company_id': companyId});
    if (profileRaw is! Map || profileRaw['company_id'] != companyId || profileRaw['profile'] is! Map) {
      throw StateError('自社の会社情報を確認できません。会社データを登録してください。');
    }
    final profile = Map<String, dynamic>.from(profileRaw['profile'] as Map);
    final company = await _client.from('companies').select('id,name,company_seal_enabled,company_seal_style')
      .eq('id', companyId).single().setHeader('Authorization', 'Bearer $_token');
    verify();
    if (company['id'] != companyId || company['name'] != profile['name']) throw StateError('会社情報が更新されました。開き直してください。');
    Map<String, dynamic> seal = {'version': 1, 'style': company['company_seal_style'] ?? 'legacy',
      'name': company['name'], 'company_id': companyId};
    try {
      final png = await _rpc('company_uploaded_seal_settings', {'p_company_id': companyId});
      if (png is! Map || png['company_id'] != companyId || png['company_name'] != company['name'] || png['enabled'] is! bool) {
        throw StateError('登録角印を確認できません。');
      }
      if (png['enabled'] == true) {
        seal = {'version': 2, 'style': 'uploaded_png', 'name': company['name'], 'company_id': companyId,
          'png_version_id': png['version_id'], 'png_base64': png['png_base64'], 'png_sha256': png['png_sha256']};
      }
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202' && e.code != '42883') rethrow;
      verify();
    }
    CompanySealSnapshot.fromJson(seal); // Exact registered asset/company validation.
    final kind = acceptance ? 'invoice' : 'payment_certificate';
    final template = await _rpc('trade_document_template', {'p_kind': kind, 'p_company': companyId});
    if (template is! Map || template['payload'] is! Map) throw StateError('工事初期文を確認できません。');
    // Only the canonical directory link authorizes an optional supplier-bank
    // lookup. Names, customer links and caller form fields never select a bank.
    final partnerId = acceptance ? null : partner['partner_company_id'];
    Map<String, dynamic>? bank;
    if (partnerId != null) {
      if (partnerId is! String || !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(partnerId)) {
        throw StateError('受注者の協力会社登録を確認できません。');
      }
      Object? result;
      var backendAbsent = false;
      try {
        result = await _rpc('partner_company_bank_read', {'p_company': companyId, 'p_partner': partnerId});
      } on PostgrestException catch (error) {
        if (!const ['PGRST202', '42883'].contains(error.code)) rethrow;
        verify(); // An absent unreleased backend retains the legacy bank-free order.
        backendAbsent = true;
      }
      if (!backendAbsent) {
        if (result is! Map || result.length != 5 || result['company_id'] != companyId ||
            result['partner_company_id'] != partnerId || result['available'] is! bool ||
            result['version'] is! int || result['version'] < 0) {
          throw StateError('受注者の振込先の所属を確認できません。');
        }
        final snapshot = result['bank'] == null ? null : PartnerCompanyBankAccount.fromJson(
          result['bank'], companyId: companyId, partnerCompanyId: partnerId);
        if ((snapshot?.bankVersion ?? 0) != result['version'] ||
            (result['available'] == false && (snapshot != null || result['version'] != 0))) {
          throw StateError('受注者の振込先の保存版を確認できません。');
        }
        bank = snapshot?.toJson();
      }
    }
    verify();
    return {'company_id': companyId, 'trade_company_id': tradeCompanyId, 'acceptance': acceptance,
      if (partnerId != null) 'partner_company_id': partnerId,
      if (bank != null) 'counterparty_bank': bank,
      'issuer': {'name': profile['name'], 'address': profile['address'] ?? '',
        'corporate_number': profile['corporate_number'] ?? '', 'representative_name': profile['representative_name'] ?? ''},
      'counterparty': {'name': partner['name'], 'address': partner['address'] ?? '',
        'corporate_number': partner['corporate_number'] ?? '', 'representative_name': partner['representative_name'] ?? ''},
      'template': Map<String, dynamic>.from(template['payload'] as Map),
      'company_seal_snapshot': seal, 'company_seal_enabled': company['company_seal_enabled'] == true};
  }
  Future<void> dispose() { invalidate(); return _disposing ??= _close(); }
  Future<void> _close() async { await _auth?.cancel(); }
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/secondary_reset_session_guard.dart';
import '../auth/app_auth_mutation_gateway.dart';

class CompanyLinkContext {
  const CompanyLinkContext(this.id, this.name, this.enabled);
  final String id;
  final String name;
  final bool enabled;
}

/// This client lease discards stale results; the SQL membership guard is authoritative.
class CompanyLinkScope {
  CompanyLinkScope._(this._identity, this._check, this._rpc, this._close) {
    _capturedIdentity = _identity();
    if (_capturedIdentity == null) _deny();
  }
  factory CompanyLinkScope.forClient(SupabaseClient client) {
    final session = client.auth.currentSession;
    if (session == null) throw StateError('ログイン状態を確認してください。');
    final owner = AppAuthMutationGateway.forClient(client);
    final admission = owner.externalFlowAdmission();
    final guard = SecondaryResetSessionGuard(
      currentSession: () => client.auth.currentSession,
      changes: client.auth.onAuthStateChange,
    );
    return CompanyLinkScope._(
      () => SecondaryResetSessionGuard.identityOf(client.auth.currentSession),
      () async {
        if (session.isExpired) throw StateError('ログイン状態を確認してください。');
        final epoch = await admission;
        if (epoch == null || !owner.isExternalFlowCurrent(epoch)) {
          throw StateError('ログイン状態を確認してください。');
        }
        await guard.checkAfterQueuedEvents();
      },
      (name, args) => client.rpc(name, params: args)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(const Duration(seconds: 20)),
      guard.close,
    );
  }
  @visibleForTesting
  factory CompanyLinkScope.test({required String? Function() identity,
    required Future<void> Function() check,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc}) =>
      CompanyLinkScope._(identity, check, rpc, () async {});
  final String? Function() _identity;
  final Future<void> Function() _check;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  final Future<void> Function() _close;
  late final String? _capturedIdentity;
  bool _retired = false;
  int _generation = 0;
  String? _company;
  List<CompanyLinkContext> _contexts = const [];
  int get generation => _generation;
  String? get company => _company;
  List<CompanyLinkContext> get contexts => List.unmodifiable(_contexts);
  Never _deny() { _retired = true; throw StateError('会社またはログイン状態が変わりました。開き直してください。'); }
  void requireGeneration(int generation) {
    if (_retired || _identity() != _capturedIdentity || generation != _generation) _deny();
  }
  void select(String company) {
    requireGeneration(_generation);
    if (!_contexts.any((c) => c.id == company)) _deny();
    if (_company != company) { _company = company; _generation++; }
  }
  Future<Object?> _call(String name, Map<String, dynamic> args, {bool scoped = true}) async {
    final generation = _generation;
    final company = _company;
    requireGeneration(generation);
    await _check(); requireGeneration(generation);
    if (scoped && company == null) throw StateError('操作する自社を選択してください。');
    final value = await _rpc(name, {...args, if (scoped) 'p_expected_company': company});
    await _check(); requireGeneration(generation);
    if (_company != company) _deny();
    return value;
  }
  Future<void> loadContexts() async {
    final raw = await _call('trade_company_link_contexts', {}, scoped: false);
    if (raw is! Map || !_keys(raw, {'contract_version','actor_id','session_id','companies'}) ||
        raw['contract_version'] is! int || raw['contract_version'] != 1 ||
        '${raw['actor_id']}/${raw['session_id']}' != _capturedIdentity || raw['companies'] is! List) { _deny(); }
    final values = <CompanyLinkContext>[];
    for (final value in raw['companies'] as List) {
      if (value is! Map || !_keys(value, {'company_id','company_name','enabled'}) ||
          value['company_id'] is! String || !_uuid.hasMatch(value['company_id'] as String) ||
          value['company_name'] is! String || value['enabled'] is! bool ||
          values.any((c) => c.id == value['company_id'])) { _deny(); }
      values.add(CompanyLinkContext(value['company_id'] as String, value['company_name'] as String, value['enabled'] as bool));
    }
    _contexts = values;
    if (_company != null && !values.any((c) => c.id == _company)) _deny();
    if (_company == null && values.length == 1) select(values.single.id);
  }
  Future<Map<String,dynamic>> workspace() async {
    final value = await _call('trade_company_link_workspace', {});
    if (value is! Map) _deny();
    return Map<String,dynamic>.from(value);
  }
  Future<void> setEnabled(bool enabled) async { await _call('set_trade_company_link_enabled', {'p_enabled':enabled}); }
  Future<List<Map<String,dynamic>>> search(String query) async {
    final value = await _call('search_trade_company_links', {'p_query':query.trim()});
    if (value is! List || value.any((v) => v is! Map)) _deny();
    return [for (final v in value) Map<String,dynamic>.from(v as Map)];
  }
  Future<void> request({required String target, required String role, required DateTime month}) async {
    await _call('request_trade_company_link', {'p_target_company_id':target,'p_local_role':role,
      'p_start_month':'${month.year}-${month.month.toString().padLeft(2,'0')}-01'});
  }
  Future<void> respond(String id, String action) async { await _call('respond_trade_company_link', {'p_request_id':id,'p_action':action}); }
  Future<void> close() async { _retired = true; await _close(); }
  static bool _keys(Map value, Set<String> keys) => value.length == keys.length && value.keys.every(keys.contains);
  static final _uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$', caseSensitive:false);
}

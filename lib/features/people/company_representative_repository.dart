import 'dart:async';
import '../../data/supabase_backend.dart';

class CompanyRepresentativeSnapshot {
  CompanyRepresentativeSnapshot._(this.companyId, this.name, this.representative, this.value);
  final String companyId, name, representative;
  final Map<String, dynamic> value;
}
class CompanyRepresentativeRepository {
  CompanyRepresentativeRepository.forTesting({
    required String? Function() actor, required String? Function() token,
    required Stream<({String? actor, String? token})> changes,
    required Future<List<Map<String, dynamic>>> Function() memberships,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
  }) : _actor = actor, _token = token, _initialActor = actor(),
       _initialToken = token(), _memberships = memberships, _rpc = rpc {
    _subscription = changes.listen((value) {
      if (value.actor != _initialActor || value.token != _initialToken) { revoke(); }
    }, onError: (Object _) { revoke(); }, onDone: revoke);
  }
  static CompanyRepresentativeRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) { return null; }
    final client = SupabaseBackend.client;
    final token = client.auth.currentSession?.accessToken;
    final actor = client.auth.currentUser?.id;
    if (token == null || actor == null) { return null; }
    return CompanyRepresentativeRepository.forTesting(
      actor: () => client.auth.currentUser?.id,
      token: () => client.auth.currentSession?.accessToken,
      changes: client.auth.onAuthStateChange.map((event) => (
        actor: event.session?.user.id, token: event.session?.accessToken,
      )),
      memberships: () async {
        final rows = await client.from('company_members').select('company_id, role')
            .eq('user_id', actor).setHeader('Authorization', 'Bearer $token');
        return List<Map<String, dynamic>>.from(rows);
      },
      rpc: (action, data) async => client.rpc(action, params: data)
          .setHeader('Authorization', 'Bearer $token'),
    );
  }
  final String? Function() _actor, _token;
  final String? _initialActor, _initialToken;
  final Future<List<Map<String, dynamic>>> Function() _memberships;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  late final StreamSubscription<({String? actor, String? token})> _subscription;
  final Set<String> _allowed = {};
  String? _selected;
  int _epoch = 0;
  bool _revoked = false, _unknown = false;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  Stream<void> get invalidations => _invalidations.stream;
  static final _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  void revoke() { if (!_revoked) { _revoked = true; _epoch++; _invalidations.add(null); } }
  void _check([String? company, int? epoch]) {
    if (_revoked || !_uuid.hasMatch(_initialActor ?? '') ||
        (_initialToken ?? '').isEmpty || _actor() != _initialActor || _token() != _initialToken) {
      revoke();
      throw StateError('ログイン状態が変わりました。会社データを開き直してください。');
    }
    if (company != null && (!_allowed.contains(company) || _selected != company || epoch != _epoch)) {
      throw StateError('選択した会社が変わりました。読み込み直してください。');
    }
  }
  CompanyRepresentativeSnapshot _parse(Object? raw, String company) {
    if (raw is! Map || raw['company_id'] != company ||
        raw['version'] is! int || (raw['version'] as int) < 0 ||
        raw['profile'] is! Map || raw['ready'] is! bool) {
      throw StateError('会社代表者の設定を確認できません。');
    }
    final profile = Map<String, dynamic>.from(raw['profile'] as Map);
    final rep = profile['representative_name'];
    if (profile['name'] is! String || (rep != null && rep is! String) ||
        (rep is String && rep.runes.length > 80)) {
      throw StateError('会社代表者の設定を確認できません。');
    }
    return CompanyRepresentativeSnapshot._(company, profile['name'] as String,
      rep as String? ?? '', Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(raw)));
  }
  /// All manageable memberships. No LIMIT 1 and no implicit company selection.
  Future<List<({String id, String name})>> choices() async {
    _check();
    final rows = await _memberships();
    _check();
    _allowed.clear();
    for (final row in rows) {
      if (!const {'owner', 'admin'}.contains(row['role'])) { continue; }
      final id = row['company_id'];
      if (id is! String || !_uuid.hasMatch(id) || !_allowed.add(id)) {
        throw StateError('所属会社を確認できません。');
      }
    }
    final result = <({String id, String name})>[];
    for (final id in _allowed) {
      final snapshot = _parse(await _rpc('read_partner_company_profile', {'p_company_id': id}), id);
      _check();
      result.add((id: id, name: snapshot.name));
    }
    return List.unmodifiable(result);
  }
  Future<CompanyRepresentativeSnapshot> selectCompany(String id) async {
    _check();
    if (!_allowed.contains(id)) { throw StateError('管理できる会社を選択してください。'); }
    _selected = id; _epoch++; _unknown = true;
    return reload();
  }
  Future<CompanyRepresentativeSnapshot> reload() async {
    final company = _selected;
    final epoch = _epoch;
    if (company == null) { throw StateError('代表者を登録する会社を選択してください。'); }
    _check(company, epoch);
    final raw = await _rpc('read_partner_company_profile', {'p_company_id': company});
    _check(company, epoch);
    final value = _parse(raw, company);
    _unknown = false;
    return value;
  }
  Future<CompanyRepresentativeSnapshot> save(CompanyRepresentativeSnapshot expected, String draft) async {
    final company = _selected;
    final epoch = _epoch;
    if (company == null || expected.companyId != company || _unknown) {
      throw StateError('選択した会社の設定を読み込み直してください。');
    }
    _check(company, epoch);
    final normalized = draft.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.runes.length > 80) { throw StateError('代表者名は80文字以内で入力してください。'); }
    _unknown = true;
    try {
      final response = _parse(await _rpc('save_partner_company_representative', {
        'p_company_id': company, 'p_expected': expected.value, 'p_representative_name': normalized,
      }), company);
      _check(company, epoch);
      final fresh = await reload();
      _check(company, epoch);
      if (fresh.value['version'] != response.value['version'] || fresh.representative != response.representative) {
        throw StateError('会社情報が更新されました。入力内容を確認して読み込み直してください。');
      }
      return fresh;
    } catch (_) { _unknown = true; rethrow; }
  }
  Future<void> dispose() async { revoke(); await _subscription.cancel(); await _invalidations.close(); }
}

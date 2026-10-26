import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'company_work_category_policy.dart';

class CompanyWorkCategorySnapshot {
  const CompanyWorkCategorySnapshot({required this.actorId, required this.companyId,
    required this.revision, required this.canManage, required this.policy});
  final String actorId, companyId;
  final int revision;
  final bool canManage;
  final CompanyWorkCategoryPolicy? policy;
  factory CompanyWorkCategorySnapshot.parse(Object? value, {required String actorId, required String companyId}) {
    if (value is! Map || value['schema'] != 1 || value['actor_id'] != actorId ||
        value['company_id'] != companyId || value['can_manage'] is! bool ||
        value['revision'] is! int || (value['revision'] as int) < 0 ||
        ((value['revision'] == 0) != (value['policy'] == null))) {
      throw const FormatException('会社の勤務区分設定が一致しません。再読込してください。');
    }
    return CompanyWorkCategorySnapshot(actorId: actorId, companyId: companyId,
      revision: value['revision'] as int, canManage: value['can_manage'] as bool,
      policy: value['policy'] == null ? null : CompanyWorkCategoryPolicy.parse(value['policy']));
  }
}

class CompanyWorkCategoryRepository {
  CompanyWorkCategoryRepository(this._client);
  final SupabaseClient _client;
  static CompanyWorkCategoryRepository? maybeCreate() => !SupabaseBackend.isInitialized ||
      SupabaseBackend.client.auth.currentUser == null ? null : CompanyWorkCategoryRepository(SupabaseBackend.client);
  static String? _identity(Session? session) {
    if (session == null) return null;
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3) return null;
      final value = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (value is! Map || value['sub'] != session.user.id || value['session_id'] is! String ||
          !RegExp(r'^[0-9a-f-]{36}$').hasMatch(value['session_id'] as String)) return null;
      return '${session.user.id}/${value['session_id']}';
    } on Object { return null; }
  }
  Future<CompanyWorkCategorySnapshot> _request(String companyId, String rpc, Map<String, dynamic> params) async {
    final session = _client.auth.currentSession;
    final actor = session?.user.id, identity = _identity(session);
    if (actor == null || identity == null) throw StateError('ログイン状態を確認してください。');
    var changed = false;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (_identity(event.session) != identity) changed = true;
    });
    try {
      final raw = await _client.rpc(rpc, params: params);
      await Future<void>.delayed(Duration.zero);
      if (changed || _identity(_client.auth.currentSession) != identity) throw StateError('ログイン状態が変わりました。設定を開き直してください。');
      return CompanyWorkCategorySnapshot.parse(raw, actorId: actor, companyId: companyId);
    } on PostgrestException catch (error) {
      if (error.code == 'PT409' || error.code == '40001') throw StateError('会社の設定が更新されました。再読込してください。');
      if (error.code == '42501') throw StateError('会社の勤務区分設定を操作する権限がありません。');
      throw StateError('会社の勤務区分設定を取得・保存できません。設定は自動適用しません。');
    } finally { await subscription.cancel(); }
  }
  Future<CompanyWorkCategorySnapshot> load(String companyId) => _request(companyId,
    'read_company_work_category_policy', {'p_company_id': companyId});
  Future<String?> proposeForSource(CompanyWorkCategorySnapshot snapshot, {
    required String sourceClockInId, required String workerId, required DateTime workDate}) async {
    final policy = snapshot.policy;
    if (policy == null || sourceClockInId.isEmpty || workerId.isEmpty) return null;
    final identity = _identity(_client.auth.currentSession);
    if (identity == null || _client.auth.currentUser?.id != snapshot.actorId) return null;
    var changed = false;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (_identity(event.session) != identity) changed = true;
    });
    try {
      final rows = await _client.from('attendance_verifications')
        .select('id,company_id,worker_id,event_type,work_date,confirmed_at')
        .eq('id', sourceClockInId).eq('company_id', snapshot.companyId)
        .eq('worker_id', workerId).eq('event_type', 'clock_in').limit(2);
      await Future<void>.delayed(Duration.zero);
      if (changed || _identity(_client.auth.currentSession) != identity || rows.length != 1) return null;
      final row = rows.single;
      if (row['id'] != sourceClockInId || row['company_id'] != snapshot.companyId ||
          row['worker_id'] != workerId || row['event_type'] != 'clock_in' ||
          row['work_date'] != CompanyWorkCategoryPolicy.dateKey(workDate)) return null;
      final raw = row['confirmed_at'];
      if (raw is! String || !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw)) return null;
      final clockIn = DateTime.tryParse(raw);
      if (clockIn == null) return null;
      return policy.propose(clockInAt: clockIn, workDate: workDate);
    } on Object { return null; }
    finally { await subscription.cancel(); }
  }
  Future<CompanyWorkCategorySnapshot> save(CompanyWorkCategorySnapshot before, CompanyWorkCategoryPolicy policy) {
    if (!before.canManage) throw StateError('勤務区分設定は管理者のみ変更できます。');
    final validated = CompanyWorkCategoryPolicy.parse(policy.toJson());
    return _request(before.companyId, 'save_company_work_category_policy', {'p_company_id': before.companyId,
      'p_expected_revision': before.revision, 'p_policy': validated.toJson()});
  }
}

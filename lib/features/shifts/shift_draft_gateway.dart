import 'shift_draft_request.dart';

/// The caller supplies an authenticated Supabase RPC invoker. The server is the
/// authority for roles, company isolation, active sites and revision conflicts.
class ShiftDraftGateway {
  const ShiftDraftGateway(this.call);
  final Future<Object?> Function(String name, Map<String, Object?> params) call;

  Future<void> save(List<ShiftDraftRequest> requests) async {
    if (requests.isEmpty || requests.length > 100) throw const FormatException('従業員を選択してください。');
    final company = requests.first.companyId;
    if (requests.any((r) => r.companyId != company)) throw const FormatException('会社を確認してください。');
    final payload = requests.map((r) => r.toJson()).toList(growable: false);
    final expected = {for (final r in requests) '${r.workerId}:${r.toJson()['work_date']}': r.revision + 1};
    if (expected.length != requests.length) throw const FormatException('勤務日が重複しています。');
    final result = await call('save_shift_drafts', {'p_company': company, 'p_rows': payload});
    if (result is! List || result.length != requests.length) {
      throw const FormatException('保存結果を確認できません。再読み込みしてください。');
    }
    final observed = <String, int>{};
    for (final row in result) {
      if (row is! Map || row['worker_id'] is! String || row['work_date'] is! String || row['revision'] is! int) {
        throw const FormatException('保存結果を確認できません。再読み込みしてください。');
      }
      final key = '${row['worker_id']}:${row['work_date']}';
      if (observed.containsKey(key)) throw const FormatException('保存結果を確認できません。再読み込みしてください。');
      observed[key] = row['revision'] as int;
    }
    if (observed.length != expected.length || expected.entries.any((e) => observed[e.key] != e.value)) {
      throw const FormatException('保存結果を確認できません。再読み込みしてください。');
    }
  }
}

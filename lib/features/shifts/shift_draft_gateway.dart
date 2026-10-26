import 'shift_draft_request.dart';

/// The caller supplies an authenticated Supabase RPC invoker. The server is the
/// authority for roles, company isolation, active sites and revision conflicts.
class ShiftDraftGateway {
  const ShiftDraftGateway(this.call);
  final Future<Object?> Function(String name, Map<String, Object?> params) call;

  /// Read server-authorized management drafts; an invalid response is never
  /// treated as an empty schedule because that could hide saved work.
  Future<List<ShiftDraftRequest>> listMonth(String company, DateTime month) async {
    if (company.trim().isEmpty) throw const FormatException('会社を確認してください。');
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    String date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final result = await call('list_shift_drafts', {
      'p_company': company, 'p_from': date(first), 'p_to': date(last),
    });
    if (result is! List) throw const FormatException('下書きを確認できません。');
    final items = <ShiftDraftRequest>[];
    final keys = <String>{};
    for (final row in result) {
      if (row is! Map || row['worker_id'] is! String || row['work_date'] is! String ||
          (row['site_id'] != null && row['site_id'] is! String) || row['holiday'] is! bool ||
          row['night'] is! bool || row['check_late'] is! bool || row['check_early'] is! bool ||
          row['start_minute'] is! int || row['end_minute'] is! int || row['revision'] is! int) {
        throw const FormatException('下書きを確認できません。');
      }
      final rawDate = row['work_date'] as String;
      final parsed = DateTime.tryParse(rawDate);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(rawDate) || parsed == null ||
          date(parsed) != rawDate || parsed.isBefore(first) || parsed.isAfter(last) ||
          (row['revision'] as int) <= 0 || !keys.add('${row['worker_id']}:$rawDate')) {
        throw const FormatException('下書きを確認できません。');
      }
      final draft = ShiftDraftRequest(companyId: company, workerId: row['worker_id'] as String,
        siteId: row['site_id'] as String?, workDate: parsed, holiday: row['holiday'] as bool,
        night: row['night'] as bool, startMinute: row['start_minute'] as int,
        endMinute: row['end_minute'] as int, checkLate: row['check_late'] as bool,
        checkEarly: row['check_early'] as bool, revision: row['revision'] as int);
      if (draft.validate() != null || draft.startMinute < 0 || draft.startMinute >= 1440 ||
          draft.endMinute < 0 || draft.endMinute >= 1440) {
        throw const FormatException('下書きを確認できません。');
      }
      items.add(draft);
    }
    return List.unmodifiable(items);
  }

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

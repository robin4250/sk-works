import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class GroupCheckoutCandidate {
  const GroupCheckoutCandidate({required this.sourceId, required this.workerId,
    required this.name, required this.workDate, this.clockOutAt});
  final String sourceId;
  final String workerId;
  final String name;
  final DateTime workDate;
  final DateTime? clockOutAt;
  bool get isOpen => clockOutAt == null;
}

List<GroupCheckoutCandidate> parseGroupCheckoutCandidates(Object? value, DateTime expectedDate) {
  if (value is! List) {
    throw StateError('現場メンバーを確認できません');
  }
  final ids = <String>{};
  final workers = <String>{};
  final result = <GroupCheckoutCandidate>[];
  for (final raw in value) {
    if (raw is! Map) {
      throw StateError('現場メンバーの記録を確認できません');
    }
    final source = raw['source_clock_in_id']?.toString() ?? '';
    final worker = raw['worker_id']?.toString() ?? '';
    final dateText = raw['work_date']?.toString() ?? '';
    final date = DateTime.tryParse(dateText);
    final outText = raw['clock_out_at']?.toString();
    final out = outText == null ? null : DateTime.tryParse(outText);
    if (source.isEmpty || worker.isEmpty || !ids.add(source) || !workers.add(worker) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText) || date == null ||
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' != dateText ||
        date.year != expectedDate.year || date.month != expectedDate.month || date.day != expectedDate.day ||
        (outText != null && out == null)) {
      throw StateError('勤務日または対象勤務が一致しません。再確認してください');
    }
    result.add(GroupCheckoutCandidate(sourceId: source, workerId: worker,
      name: raw['worker_name']?.toString() ?? '氏名未登録', workDate: date, clockOutAt: out));
  }
  return List.unmodifiable(result);
}

/// Keeps an identical request token for retries; changed selections require a new token.
class GroupCheckoutRequest {
  GroupCheckoutRequest({required this.anchorId, required Iterable<String> sourceIds})
      : sourceIds = List.unmodifiable(sourceIds.toSet().toList()..sort()),
        token = _newToken() {
    if (anchorId.isEmpty || this.sourceIds.isEmpty || this.sourceIds.any((id) => id.isEmpty)) {
      throw ArgumentError('対象の勤務を選択してください');
    }
  }
  final String anchorId;
  final List<String> sourceIds;
  final String token;
  bool matches(Iterable<String> ids) {
    final sorted = ids.toSet().toList()..sort();
    return sorted.length == sourceIds.length &&
      List.generate(sorted.length, (i) => sorted[i] == sourceIds[i]).every((same) => same);
  }
  static String _newToken() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

bool groupCheckoutEnabled(Object? value, String companyId) => value is Map &&
  value['version'] == 1 && value['company_id'] == companyId && value['group_checkout_enabled'] == true;

class GroupCheckoutRepository {
  GroupCheckoutRepository(this._client);
  final SupabaseClient _client;
  static GroupCheckoutRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) {
      return null;
    }
    return GroupCheckoutRepository(SupabaseBackend.client);
  }

  Future<List<GroupCheckoutCandidate>?> loadIfEnabled(String anchorId, DateTime workDate) async {
    String? companyId;
    try {
      final anchor = await _client.from('attendance_verifications').select('company_id')
        .eq('id', anchorId).maybeSingle();
      companyId = anchor?['company_id']?.toString();
      if (companyId == null) {
        return null;
      }
      final capability = await _client.rpc('get_attendance_rollout_capabilities',
        params: {'p_company_id': companyId});
      if (!groupCheckoutEnabled(capability, companyId)) {
        return null;
      }
    } catch (_) {
      // Unavailable or unknown capability is OFF; never infer enablement.
      return null;
    }
    final value = await _client.rpc('group_checkout_candidates',
      params: {'p_source_clock_in_id': anchorId});
    return parseGroupCheckoutCandidates(value, workDate);
  }

  Future<void> commit(GroupCheckoutRequest request) async {
    final value = await _client.rpc('commit_group_checkout', params: {
      'p_source_clock_in_id': request.anchorId,
      'p_selected_source_ids': request.sourceIds,
      'p_request_token': request.token,
    });
    if (value is! List || value.length != request.sourceIds.length) {
      throw StateError('退勤結果を確認できません。同じ内容で再確認してください');
    }
    final returned = <String>{};
    for (final row in value) {
      if (row is! Map || row['clock_out_id'] == null ||
          !returned.add(row['source_clock_in_id']?.toString() ?? '')) {
        throw StateError('退勤結果を確認できません');
      }
    }
    if (!request.matches(returned)) {
      throw StateError('対象勤務と退勤結果が一致しません');
    }
  }
}

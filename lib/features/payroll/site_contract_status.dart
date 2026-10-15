/// Read-only projection of immutable proposals. A pending revision must never
/// replace the last mutually confirmed contract, including before its start.
class SiteContractStatus {
  SiteContractStatus._(this.active, this.pending, this.scheduled);
  final Map<String, dynamic>? active;
  final Map<String, dynamic>? pending;
  final Map<String, dynamic>? scheduled;
  bool get isContracted => active != null;
  String get label => pending != null
      ? (active != null ? '契約中・変更承認待ち' : '承認待ち')
      : scheduled != null
          ? (active != null ? '契約中・変更適用待ち' : '適用開始待ち')
          : active != null ? '契約中' : '未契約';

  factory SiteContractStatus.fromProposals(
    List<Map<String, dynamic>> proposals, {
    required String parentCompanyId,
    required String childCompanyId,
    required DateTime today,
  }) {
    if (parentCompanyId.isEmpty || childCompanyId.isEmpty ||
        parentCompanyId == childCompanyId) {
      throw ArgumentError('異なる双方の会社が必要です。');
    }
    final ordered = [...proposals]..sort((a, b) =>
        (b['revision'] as int).compareTo(a['revision'] as int));
    Map<String, dynamic>? active, pending, scheduled;
    final date = DateTime(today.year, today.month, today.day);
    for (final proposal in ordered) {
      final confirmations = proposal['confirmations'];
      final parties = <String>{
        if (confirmations is List)
          for (final item in confirmations)
            if (item is Map && item['company_id'] is String)
              item['company_id'] as String,
      };
      if (!parties.contains(parentCompanyId) ||
          !parties.contains(childCompanyId)) {
        pending ??= Map.unmodifiable(proposal);
        continue;
      }
      final terms = proposal['terms'];
      final start = terms is Map
          ? DateTime.tryParse('${terms['effective_from'] ?? terms['period_start']}')
          : null;
      // Malformed contracts cannot silently become effective.
      if (start == null) continue;
      final startDate = DateTime(start.year, start.month, start.day);
      if (startDate.isAfter(date)) {
        scheduled ??= Map.unmodifiable(proposal);
      } else {
        active ??= Map.unmodifiable(proposal);
      }
    }
    // Older unconfirmed proposals are history, not current pending changes.
    if (pending != null && ordered.isNotEmpty &&
        pending['revision'] != ordered.first['revision']) {
      pending = null;
    }
    return SiteContractStatus._(active, pending, scheduled);
  }
}

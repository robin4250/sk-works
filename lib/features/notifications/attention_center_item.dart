/// Unified attention data. Reading a message never completes its business task.
enum AttentionCenterState { pending, completed, rejected, cancelled, unknown, information }

class AttentionCenterItem {
  const AttentionCenterItem({
    required this.id,
    required this.source,
    required this.title,
    required this.state,
    this.body = '',
    this.metadata = const {},
    this.actionKey,
    this.actionId,
    this.targetName,
    this.targetDate,
    this.createdAt,
    this.deadline,
    this.read = false,
    this.actionable = true,
    this.evidenceRank = 0,
    this.payrollReviewerId,
    this.payrollMonth,
  });

  final String id;
  final String source;
  final String title;
  final String body;
  final Map<String, Object?> metadata;
  final AttentionCenterState state;
  final String? actionKey;
  final String? actionId;
  final String? targetName;
  final DateTime? targetDate;
  final DateTime? createdAt;
  /// Only an actual source deadline; callers must not invent one.
  final DateTime? deadline;
  final bool read;
  final bool actionable;
  /// Prefer authoritative current task evidence over historical messages.
  final int evidenceRank;
  /// Both fields must come explicitly from the payroll task payload.
  final String? payrollReviewerId;
  final String? payrollMonth;

  bool get needsAction => state == AttentionCenterState.pending && actionable;

  String get deduplicationKey {
    String part(String value) => '${value.length}:$value';
    if (actionKey == 'payroll_review' &&
        (payrollReviewerId?.isNotEmpty ?? false) &&
        RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(payrollMonth ?? '')) {
      return 'payroll:${part(payrollReviewerId!)}:${part(payrollMonth!)}';
    }
    if ((actionKey?.isNotEmpty ?? false) && (actionId?.isNotEmpty ?? false)) {
      return 'target:${part(actionKey!)}:${part(actionId!)}';
    }
    // Source-local entries without an exact target must never be guessed equal.
    return 'source:${part(source)}:${part(id)}';
  }
}

class AttentionCenterSnapshot {
  AttentionCenterSnapshot(Iterable<AttentionCenterItem> items, {required DateTime now})
      : items = _normalize(items, now);

  final List<AttentionCenterItem> items;
  int get unresolvedCount => items.where((item) => item.needsAction).length;
  bool get hasUnresolved => unresolvedCount > 0;
}

List<AttentionCenterItem> _normalize(Iterable<AttentionCenterItem> raw, DateTime now) {
  final byKey = <String, AttentionCenterItem>{};
  for (final item in raw) {
    final key = item.deduplicationKey;
    final existing = byKey[key];
    if (existing == null || item.evidenceRank > existing.evidenceRank ||
        (item.evidenceRank == existing.evidenceRank &&
            (item.createdAt?.isAfter(existing.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)) ?? false))) {
      byKey[key] = item;
    }
  }
  int category(AttentionCenterItem item) {
    if (item.needsAction) {
      if (item.deadline?.isBefore(now) ?? false) {
        return 0;
      }
      return item.deadline == null ? 2 : 1;
    }
    if (item.state == AttentionCenterState.unknown) {
      return 3;
    }
    if (item.state == AttentionCenterState.information) {
      return 5;
    }
    return 4;
  }
  final result = byKey.values.toList();
  result.sort((a, b) {
    final group = category(a).compareTo(category(b));
    if (group != 0) {
      return group;
    }
    if (a.needsAction && b.needsAction && a.deadline != null && b.deadline != null) {
      final due = a.deadline!.compareTo(b.deadline!);
      if (due != 0) {
        return due;
      }
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final created = (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
    if (created != 0) {
      return created;
    }
    return a.deduplicationKey.compareTo(b.deduplicationKey);
  });
  return List.unmodifiable(result);
}

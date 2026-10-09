/// Hand-entered monthly resident tax, separate from company percentage rates.
class ResidentTaxMonth implements Comparable<ResidentTaxMonth> {
  ResidentTaxMonth(this.year, this.month) {
    if (year < 1 || year > 9999) throw RangeError.range(year, 1, 9999, 'year');
    if (month < 1 || month > 12) throw RangeError.range(month, 1, 12, 'month');
  }
  final int year;
  final int month;
  int get _ordinal => year * 12 + month;
  @override
  int compareTo(ResidentTaxMonth other) => _ordinal.compareTo(other._ordinal);
  @override
  bool operator ==(Object other) => other is ResidentTaxMonth && year == other.year && month == other.month;
  @override
  int get hashCode => Object.hash(year, month);
  @override
  String toString() => '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

class ResidentTaxEntry {
  ResidentTaxEntry({required this.startMonth, required this.monthlyAmountYen}) {
    if (monthlyAmountYen < 0 || monthlyAmountYen > ResidentTaxSchedule.maxExactInteger) {
      throw RangeError.range(monthlyAmountYen, 0, ResidentTaxSchedule.maxExactInteger, 'monthlyAmountYen');
    }
  }
  final ResidentTaxMonth startMonth;
  final int monthlyAmountYen;
}

enum ResidentTaxSelectionStatus { unregistered, beforeFirstStart, active }

class ResidentTaxSelection {
  const ResidentTaxSelection._(this.status, this.entry);
  final ResidentTaxSelectionStatus status;
  final ResidentTaxEntry? entry;
  /// Null means no applicable registration, rather than an intentional zero.
  int? get monthlyAmountYen => entry?.monthlyAmountYen;
}

class ResidentTaxChange {
  const ResidentTaxChange._({
    required this.version,
    required this.actorId,
    required this.changedAtUtc,
    required this.before,
    required this.after,
  });
  final int version;
  final String actorId;
  final DateTime changedAtUtc;
  final ResidentTaxEntry? before;
  final ResidentTaxEntry after;
}

/// Immutable local state. Scope checks are consistency checks, not authorization.
class ResidentTaxSchedule {
  ResidentTaxSchedule._({
    required this.companyId,
    required this.workerId,
    required this.version,
    required List<ResidentTaxEntry> entries,
    required List<ResidentTaxChange> history,
  }) : entries = List.unmodifiable(entries), history = List.unmodifiable(history);

  factory ResidentTaxSchedule.empty({required String companyId, required String workerId}) {
    _requireId(companyId, 'companyId');
    _requireId(workerId, 'workerId');
    return ResidentTaxSchedule._(companyId: companyId, workerId: workerId, version: 0, entries: [], history: []);
  }
  static const maxExactInteger = 9007199254740991;
  final String companyId;
  final String workerId;
  final int version;
  /// Current effective timeline; old amounts remain in history, never erased.
  final List<ResidentTaxEntry> entries;
  final List<ResidentTaxChange> history;

  ResidentTaxSelection select({required String companyId, required String workerId, required ResidentTaxMonth payrollMonth}) {
    _checkScope(companyId, workerId);
    if (entries.isEmpty) return const ResidentTaxSelection._(ResidentTaxSelectionStatus.unregistered, null);
    ResidentTaxEntry? chosen;
    for (final entry in entries) {
      if (entry.startMonth.compareTo(payrollMonth) <= 0) chosen = entry;
      else break;
    }
    return ResidentTaxSelection._(chosen == null ? ResidentTaxSelectionStatus.beforeFirstStart : ResidentTaxSelectionStatus.active, chosen);
  }

  /// Registers a distinct start month, including future starts. Duplicate rejects.
  ResidentTaxSchedule register({
    required String companyId,
    required String workerId,
    required int expectedVersion,
    required ResidentTaxEntry entry,
    required String actorId,
    required DateTime changedAt,
  }) => _write(companyId: companyId, workerId: workerId, expectedVersion: expectedVersion, entry: entry, actorId: actorId, changedAt: changedAt, amend: false);

  /// Explicit correction at an existing start month, preserving before/after.
  ResidentTaxSchedule amend({
    required String companyId,
    required String workerId,
    required int expectedVersion,
    required ResidentTaxEntry entry,
    required String actorId,
    required DateTime changedAt,
  }) => _write(companyId: companyId, workerId: workerId, expectedVersion: expectedVersion, entry: entry, actorId: actorId, changedAt: changedAt, amend: true);

  ResidentTaxSchedule _write({
    required String companyId, required String workerId, required int expectedVersion,
    required ResidentTaxEntry entry, required String actorId, required DateTime changedAt, required bool amend,
  }) {
    _checkScope(companyId, workerId);
    _requireId(actorId, 'actorId');
    if (expectedVersion != version) throw StateError('Resident tax schedule version changed');
    if (version >= maxExactInteger) throw StateError('Resident tax schedule version limit reached');
    final index = entries.indexWhere((existing) => existing.startMonth == entry.startMonth);
    if (!amend && index >= 0) throw StateError('Duplicate resident tax start month');
    if (amend && index < 0) throw StateError('No resident tax start month to amend');
    final before = index < 0 ? null : entries[index];
    final updated = [...entries];
    if (index < 0) updated.add(entry);
    else updated[index] = entry;
    updated.sort((a, b) => a.startMonth.compareTo(b.startMonth));
    return ResidentTaxSchedule._(
      companyId: this.companyId, workerId: this.workerId, version: version + 1, entries: updated,
      history: [...history, ResidentTaxChange._(version: version + 1, actorId: actorId, changedAtUtc: changedAt.toUtc(), before: before, after: entry)],
    );
  }
  void _checkScope(String companyId, String workerId) {
    if (companyId != this.companyId || workerId != this.workerId) throw StateError('Resident tax company/worker scope mismatch');
  }
  static void _requireId(String value, String name) {
    if (value.trim().isEmpty || value != value.trim()) throw ArgumentError.value(value, name, 'ID must be nonblank and unpadded');
  }
}

/// Pure domain contract; not connected to storage, UI, or payroll calculation.
/// Values must come from administrator configuration, never guessed defaults.
class PercentRate {
  /// One unit is 0.000001 percentage points; 1% is 1000000 units.
  final int millionthsOfPercent;
  PercentRate(this.millionthsOfPercent) {
    if (millionthsOfPercent < 0 || millionthsOfPercent > 100000000) {
      throw ArgumentError.value(millionthsOfPercent, 'millionthsOfPercent');
    }
  }
  @override
  bool operator ==(Object other) => other is PercentRate &&
      other.millionthsOfPercent == millionthsOfPercent;
  @override
  int get hashCode => millionthsOfPercent.hashCode;
}

class RateMonth {
  final int year;
  final int month;
  RateMonth(this.year, this.month) {
    if (year < 1 || month < 1 || month > 12) {
      throw ArgumentError('Invalid rate month');
    }
  }
  @override
  bool operator ==(Object other) => other is RateMonth &&
      other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(year, month);
}

enum CompanyRateKind {
  healthInsurance, nursingInsurance, pensionInsurance,
  employmentInsurance, childSupport, custom,
}

/// Each share is explicit. No inferred division of total, including employment.
class RateShares {
  final PercentRate total;
  final PercentRate employee;
  final PercentRate employer;
  RateShares({required this.total, required this.employee, required this.employer}) {
    if (employee.millionthsOfPercent + employer.millionthsOfPercent !=
        total.millionthsOfPercent) {
      throw ArgumentError('Explicit shares must sum to total');
    }
  }
  @override
  bool operator ==(Object other) => other is RateShares &&
      other.total == total && other.employee == employee && other.employer == employer;
  @override
  int get hashCode => Object.hash(total, employee, employer);
}

class RateSource {
  final Uri url;
  final String publisher;
  final String documentHash;
  final DateTime checkedAt;
  /// Verified insurer, prefecture, business classification and other conditions.
  final Map<String, String> applicability;
  RateSource({required this.url, required this.publisher,
    required this.documentHash, required DateTime checkedAt,
    required Map<String, String> applicability})
      : checkedAt = checkedAt.toUtc(),
        applicability = Map.unmodifiable(applicability) {
    if (url.scheme != 'https' || url.host.isEmpty || publisher.trim().isEmpty ||
        documentHash.trim().isEmpty || applicability.isEmpty) {
      throw ArgumentError('Source and applicability evidence are required');
    }
  }
}

class CompanyRateSetting {
  final String itemId;
  final CompanyRateKind kind;
  final String label;
  final RateShares shares;
  /// These months have different meanings and must be supplied separately.
  final RateMonth insuranceMonth;
  final RateMonth payrollDeductionMonth;
  final RateMonth paymentMonth;
  final RateSource source;
  final int version;
  CompanyRateSetting({required this.itemId, required this.kind,
    required this.label, required this.shares, required this.insuranceMonth,
    required this.payrollDeductionMonth, required this.paymentMonth,
    required this.source, required this.version}) {
    if (itemId.trim().isEmpty || label.trim().isEmpty || version < 0) {
      throw ArgumentError('Invalid rate item');
    }
  }
}

/// Fetching constructs a candidate only. Verification is performed upstream;
/// this flag does not itself establish that a document is official.
class OfficialRateCandidate {
  final String candidateId;
  final CompanyRateSetting proposed;
  final bool sourceAndCompanyScopeVerified;
  OfficialRateCandidate({required this.candidateId, required this.proposed,
    required this.sourceAndCompanyScopeVerified}) {
    if (candidateId.trim().isEmpty) throw ArgumentError('Candidate ID required');
  }
}

class RateApplyConfirmation {
  final String itemId;
  final String candidateId;
  final int expectedVersion;
  /// UI must display rates, all relevant months and source before collecting this.
  final bool ratesMonthsAndSourceReviewed;
  RateApplyConfirmation({required this.itemId, required this.candidateId,
    required this.expectedVersion, required this.ratesMonthsAndSourceReviewed});
}

class RateChange {
  final CompanyRateSetting before;
  final CompanyRateSetting after;
  final String candidateId;
  final String actorId;
  final DateTime changedAt;
  RateChange._(this.before, this.after, this.candidateId, this.actorId, this.changedAt);
}

class CompanyRateState {
  final Map<String, CompanyRateSetting> settings;
  final List<RateChange> history;
  CompanyRateState({required Map<String, CompanyRateSetting> settings,
    List<RateChange> history = const []})
      : settings = Map.unmodifiable(settings), history = List.unmodifiable(history) {
    for (final entry in settings.entries) {
      if (entry.key != entry.value.itemId) throw ArgumentError('Item key mismatch');
    }
  }

  /// Returns a new state and history together. Persistence must atomically save
  /// both with a version check; this class grants no administrator permission.
  CompanyRateState apply({required OfficialRateCandidate candidate,
    required RateApplyConfirmation confirmation, required String actorId,
    required DateTime changedAt}) {
    final proposed = candidate.proposed;
    final before = settings[confirmation.itemId];
    if (before == null || before.itemId != proposed.itemId ||
        before.kind != proposed.kind || confirmation.candidateId != candidate.candidateId ||
        confirmation.expectedVersion != before.version ||
        !confirmation.ratesMonthsAndSourceReviewed ||
        !candidate.sourceAndCompanyScopeVerified || actorId.trim().isEmpty) {
      throw StateError('Explicit verified, current-version application required');
    }
    final after = CompanyRateSetting(itemId: before.itemId, kind: before.kind,
      label: proposed.label, shares: proposed.shares,
      insuranceMonth: proposed.insuranceMonth,
      payrollDeductionMonth: proposed.payrollDeductionMonth,
      paymentMonth: proposed.paymentMonth, source: proposed.source,
      version: before.version + 1);
    return CompanyRateState(settings: {...settings, before.itemId: after},
      history: [...history, RateChange._(before, after, candidate.candidateId,
        actorId, changedAt.toUtc())]);
  }
}

/// Income tax is a separately verified table reference, never a percentage item.
/// PDF registration alone does not make a table calculation-ready.
class IncomeTaxTableReference {
  final String tableId;
  final int calendarYear;
  final DateTime startsOn;
  final DateTime endsBefore;
  final Uri pdf;
  final String documentHash;
  final bool calculationRulesVerified;
  IncomeTaxTableReference({required this.tableId, required this.calendarYear,
    required this.startsOn, required this.endsBefore, required this.pdf,
    required this.documentHash, required this.calculationRulesVerified}) {
    if (tableId.trim().isEmpty || calendarYear < 1 ||
        !endsBefore.isAfter(startsOn) || pdf.scheme != 'https' ||
        pdf.host.isEmpty || documentHash.trim().isEmpty) {
      throw ArgumentError('Invalid income tax table reference');
    }
  }
}

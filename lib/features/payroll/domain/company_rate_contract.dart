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

/// A civil date in the Japanese calendar; no timezone conversion is performed.
class PayrollDate implements Comparable<PayrollDate> {
  final int year;
  final int month;
  final int day;
  PayrollDate(this.year, this.month, this.day) {
    final checked = DateTime.utc(year, month, day);
    if (year < 1 || checked.year != year || checked.month != month || checked.day != day) {
      throw ArgumentError('Invalid payroll date');
    }
  }
  @override
  int compareTo(PayrollDate other) =>
      (year * 10000 + month * 100 + day).compareTo(
        other.year * 10000 + other.month * 100 + other.day);
}

enum IncomeTaxTableKind { monthly, daily, bonus, computerCalculation }

/// Registration, official verification, calculation readiness and permission
/// to publish shared data are separate states. No tax amounts are inferred.
class IncomeTaxTableReference {
  final String tableId;
  final String ownerCompanyId;
  final int calendarYear;
  final IncomeTaxTableKind kind;
  final PayrollDate startsOn;
  final PayrollDate endsBefore;
  final Uri pdf;
  final String documentHash;
  final bool officialDocumentVerified;
  final bool calculationRulesVerified;
  final bool commonDataApproved;
  IncomeTaxTableReference({required this.tableId, required this.ownerCompanyId,
    required this.calendarYear, required this.kind,
    required this.startsOn, required this.endsBefore, required this.pdf,
    required this.documentHash, this.officialDocumentVerified = false,
    this.calculationRulesVerified = false, this.commonDataApproved = false}) {
    if (tableId.trim().isEmpty || ownerCompanyId.trim().isEmpty || calendarYear < 1 ||
        endsBefore.compareTo(startsOn) <= 0 || startsOn.year != calendarYear ||
        endsBefore.compareTo(PayrollDate(calendarYear + 1, 1, 1)) > 0 ||
        pdf.scheme != 'https' || pdf.host.isEmpty || documentHash.trim().isEmpty ||
        (calculationRulesVerified && !officialDocumentVerified) ||
        (commonDataApproved && !officialDocumentVerified)) {
      throw ArgumentError('Invalid income tax table reference or verification state');
    }
  }

  bool contains(PayrollDate date) =>
      startsOn.compareTo(date) <= 0 && date.compareTo(endsBefore) < 0;
}

/// A company's explicitly registered schedule. Advancing the supplied civil
/// date selects the next ready table without discarding historical versions.
/// Approval flags must be provided by trusted verification/publication flows;
/// this model neither verifies PDFs nor authorizes their approval.
class IncomeTaxTableRegistry {
  final String companyId;
  final List<IncomeTaxTableReference> registered;
  final List<IncomeTaxTableReference> priorVerificationStates;
  IncomeTaxTableRegistry({required this.companyId,
    List<IncomeTaxTableReference> registered = const [],
    List<IncomeTaxTableReference> priorVerificationStates = const []})
      : registered = List.unmodifiable(registered),
        priorVerificationStates = List.unmodifiable(priorVerificationStates) {
    if (companyId.trim().isEmpty) throw ArgumentError('Company ID required');
    for (var i = 0; i < registered.length; i++) {
      final table = registered[i];
      if (table.ownerCompanyId != companyId && !table.commonDataApproved) {
        throw ArgumentError('Another company private upload cannot be registered');
      }
      for (var j = 0; j < i; j++) {
        final previous = registered[j];
        if (table.tableId == previous.tableId ||
            (table.kind == previous.kind &&
             table.startsOn.compareTo(previous.endsBefore) < 0 &&
             previous.startsOn.compareTo(table.endsBefore) < 0)) {
          throw ArgumentError('Duplicate table ID or overlapping table period');
        }
      }
    }
  }

  IncomeTaxTableRegistry register(IncomeTaxTableReference table) =>
      IncomeTaxTableRegistry(companyId: companyId, registered: [...registered, table],
        priorVerificationStates: priorVerificationStates);

  /// Changes verification state only for the exact registered document/period.
  /// Corrected documents require a new schedule instead of silent replacement.
  IncomeTaxTableRegistry recordVerification(IncomeTaxTableReference verified) {
    final index = registered.indexWhere((table) => table.tableId == verified.tableId);
    if (index < 0) throw StateError('Table is not registered');
    final old = registered[index];
    if (old.ownerCompanyId != verified.ownerCompanyId || old.kind != verified.kind ||
        old.calendarYear != verified.calendarYear || old.pdf != verified.pdf ||
        old.documentHash != verified.documentHash ||
        old.startsOn.compareTo(verified.startsOn) != 0 ||
        old.endsBefore.compareTo(verified.endsBefore) != 0) {
      throw StateError('Verification cannot replace document identity or period');
    }
    final revised = [...registered];
    revised[index] = verified;
    return IncomeTaxTableRegistry(companyId: companyId, registered: revised,
      priorVerificationStates: [...priorVerificationStates, old]);
  }

  /// No fallback to an expired table or a merely uploaded PDF.
  IncomeTaxTableReference? select({required PayrollDate date,
    required IncomeTaxTableKind kind}) {
    for (final table in registered) {
      if (table.kind == kind && table.calendarYear == date.year &&
          table.contains(date) && table.officialDocumentVerified &&
          table.calculationRulesVerified &&
          (table.ownerCompanyId == companyId || table.commonDataApproved)) {
        return table;
      }
    }
    return null;
  }
}

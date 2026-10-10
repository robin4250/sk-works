import 'company_payroll_rates_repository.dart';
import 'payroll_rate_month_picker.dart';

const initialOfficialRateKinds = <String>{
  'health_insurance',
  'nursing_insurance',
  'pension_insurance',
  'employment_insurance',
};

enum InitialOfficialRateResult { preserved, initialized, fallback }

/// Reuses the official fetcher; approved fallback is atomic and explicitly labelled.
class InitialOfficialCompanyRates {
  InitialOfficialCompanyRates({
    required this.repository,
    required this.fetcher,
    required this.loadAddress,
    required this.commit,
    required this.isCurrent,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final CompanyPayrollRatesRepository repository;
  final OfficialCompanyPayrollRateFetcher fetcher;
  final Future<String> Function() loadAddress;
  final Future<bool> Function(
    int scopeVersion,
    Map<String, String> candidates,
    bool fallback,
  )
  commit;
  final bool Function() isCurrent;
  final DateTime Function() now;

  void _check() {
    if (!isCurrent()) throw StateError('Session changed');
  }

  Future<InitialOfficialRateResult> run(String companyId) async {
    _check();
    var data = await repository.read(companyId);
    _check();
    if (!data.canEdit) return InitialOfficialRateResult.preserved;
    if (data.items.isNotEmpty) {
      return hasInitialReference(data)
          ? InitialOfficialRateResult.fallback
          : InitialOfficialRateResult.preserved;
    }
    if (data.companyScope == null) {
      final address = (await loadAddress()).trim();
      _check();
      final prefectures = companyPayrollScopePrefectures
          .where(address.startsWith)
          .toList();

      // Explicitly requested defaults; never replace an existing company scope.
      await repository.saveScope(
        companyId: companyId,
        expectedVersion: 0,
        value: {
          'insurer': 'kyokai',
          'prefecture': prefectures.length == 1 ? prefectures.single : null,
          'employment_business': 'construction',
        },
      );
      _check();
      data = await repository.read(companyId);
      _check();
    }
    if (!data.canEdit) return InitialOfficialRateResult.preserved;
    if (data.items.isNotEmpty) {
      return hasInitialReference(data)
          ? InitialOfficialRateResult.fallback
          : InitialOfficialRateResult.preserved;
    }
    final scope = data.companyScope;
    if (scope == null || scope.value['insurer'] != 'kyokai') {
      throw StateError('Company conditions require review');
    }
    final months = {
      for (final entry in payrollRateStartingMonths(now()).entries)
        entry.key: '${entry.value}-01',
    };
    final oldIds = data.candidates.map((candidate) => candidate.id).toSet();
    var fallback = false;
    final selected = <String, String>{};
    try {
      await fetcher.fetchOfficial(companyId, months);
      _check();
      data = await repository.read(companyId);
      _check();
      if (!data.canEdit) return InitialOfficialRateResult.preserved;
      if (data.items.isNotEmpty) {
        return hasInitialReference(data)
            ? InitialOfficialRateResult.fallback
            : InitialOfficialRateResult.preserved;
      }
      if (data.companyScope?.version != scope.version) {
        throw StateError('Company scope changed');
      }
      for (final kind in initialOfficialRateKinds) {
        final matches = data.candidates
            .where(
              (candidate) =>
                  candidate.itemId == kind &&
                  candidate.value['kind'] == kind &&
                  !oldIds.contains(candidate.id) &&
                  candidate.scopeVersion == scope.version &&
                  months.entries.every(
                    (month) => candidate.value[month.key] == month.value,
                  ),
            )
            .toList();
        if (matches.length != 1) {
          throw StateError('Fresh official rates incomplete');
        }
        selected[kind] = matches.single.id;
      }
      _check();
    } catch (_) {
      _check();
      fallback = true;
      selected.clear();
    }
    _check();
    final initialized = await commit(scope.version, selected, fallback);
    _check();
    return initialized
        ? (fallback
              ? InitialOfficialRateResult.fallback
              : InitialOfficialRateResult.initialized)
        : InitialOfficialRateResult.preserved;
  }
}

bool hasInitialReference(CompanyPayrollRatesData data) => data.items.any(
  (item) =>
      (item.value['source'] as Map?)?['applicability'] is Map &&
      ((item.value['source'] as Map)['applicability'] as Map).containsKey(
        'initial_reference',
      ),
);

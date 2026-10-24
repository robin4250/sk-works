import '../../data/supabase_backend.dart';
import '../payroll/company_common_allowance_repository.dart';
import 'company_allowance_label_repository.dart';

/// Read-only enrichment. The names endpoint intentionally remains price-free.
/// The separate admin reader enforces its existing owner/admin/viewer policy.
class CompanyAllowanceCurrentPriceRepository implements CompanyAllowanceLabelSource {
  CompanyAllowanceCurrentPriceRepository({required this.labels,
    required this.readPrices, required this.actor, required this.session,
    required this.sessionValid});
  final CompanyAllowanceLabelSource labels;
  final Future<CompanyCommonAllowanceState> Function(String) readPrices;
  final String? Function() actor, session;
  final bool Function() sessionValid;

  static CompanyAllowanceCurrentPriceRepository? maybeCreate() {
    final labels = SupabaseCompanyAllowanceLabelRepository.maybeCreate();
    final prices = SupabaseCompanyCommonAllowanceRepository.maybeCreate();
    if (labels == null || prices == null) return null;
    final client = SupabaseBackend.client;
    return CompanyAllowanceCurrentPriceRepository(labels: labels,
      readPrices: prices.read, actor: () => client.auth.currentUser?.id,
      session: () => client.auth.currentSession?.accessToken,
      sessionValid: () => client.auth.currentSession?.isExpired == false);
  }

  @override Future<CompanyAllowanceLabelSnapshot> read(String companyId) async {
    final initialActor = actor(), initialSession = session();
    void check() {
      if (initialActor == null || initialSession == null || initialSession.isEmpty ||
          actor() != initialActor || session() != initialSession || !sessionValid()) {
        throw StateError('ログイン状態が変わりました。再読み込みしてください');
      }
    }
    check();
    final names = await labels.read(companyId);
    check();
    if (names.companyId != companyId) throw const FormatException('会社が一致しません');
    CompanyCommonAllowanceState? prices;
    try {
      prices = await readPrices(companyId).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Permission denied and network failure retain names, never invent zero.
    }
    check();
    return attachCurrentPrices(names, prices);
  }

  static CompanyAllowanceLabelSnapshot attachCurrentPrices(
      CompanyAllowanceLabelSnapshot names, CompanyCommonAllowanceState? prices) {
    final matched = prices != null && prices.companyId == names.companyId &&
        prices.version == names.version &&
        prices.expectedSource['legacy_version'] == names.legacyVersion;
    int? price(CompanyAllowanceLabel item) {
      if (!matched || prices == null || item.id == null) return null;
      final legacy = item.origin == 'company_legacy';
      final rows = legacy ? prices.legacyRefs : prices.items;
      final matches = rows.where((row) => row['id'] == item.id &&
        row['name'] == item.name && row['unit'] == item.unit &&
        row['section'] == item.section &&
        (legacy
          ? row['slot'] == item.legacySlot && row['generation'] == item.generation &&
            row['applicability'] == item.payrollType &&
            row['source_unit'] == item.displayUnit &&
            item.registrationVersion == names.legacyVersion
          : row['payroll_type'] == item.payrollType && item.generation == null &&
            item.registrationVersion == names.version)).toList();
      if (matches.length != 1) return null;
      final value = matches.single['amount_yen'];
      return value is int && value >= 0 && value <= 2147483647 ? value : null;
    }
    return CompanyAllowanceLabelSnapshot(companyId: names.companyId,
      version: names.version, legacyVersion: names.legacyVersion,
      items: List.unmodifiable(names.items.map((item) => CompanyAllowanceLabel(
        id: item.id, name: item.name, unit: item.unit, generation: item.generation,
        origin: item.origin, payrollType: item.payrollType, section: item.section,
        displayUnit: item.displayUnit, legacySlot: item.legacySlot,
        registrationVersion: item.registrationVersion, currentRateYen: price(item)))));
  }
}

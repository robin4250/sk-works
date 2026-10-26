import 'payroll_standard_remuneration.dart';

/// Verified official retrieval metadata, retained with the existing rate source.
/// An unknown or changed table must be reviewed before the built-in conversion
/// can be represented as matching that source. Historical rates without this
/// metadata remain readable and are not relabelled as newly retrieved.
class PayrollOfficialRemunerationTable {
  const PayrollOfficialRemunerationTable._(this.bases, this.lowerBounds,
      this.sourceUrl, this.documentHash, this.effectiveFrom, this.verificationUrl);
  final List<int> bases, lowerBounds;
  final String sourceUrl, documentHash, effectiveFrom;
  final String? verificationUrl;
  int get minimumYen => bases.first;
  int get maximumYen => bases.last;
  int get minimumIncomeExclusiveYen => lowerBounds[1];
  int get maximumIncomeInclusiveYen => lowerBounds.last;

  static const keys = <String>{
    'remuneration_bases_csv', 'remuneration_lower_bounds_csv',
    'remuneration_source_url', 'remuneration_document_hash',
    'remuneration_effective_from', 'remuneration_table_version',
    'remuneration_verification_url', 'remuneration_verification_hash',
  };

  static PayrollOfficialRemunerationTable? fromRate(Map value) {
    final source = value['source'];
    final app = source is Map ? source['applicability'] : null;
    if (app is! Map || !app.keys.any((key) =>
        key is String && key.startsWith('remuneration_'))) { return null; }
    Never invalid() => throw const FormatException(
        '公式の標準報酬月額表を確認できません。現在の設定を保持して再取得してください');
    if (keys.where((key) => !key.startsWith('remuneration_verification_')).any((key) => app[key] is! String || (app[key] as String).isEmpty ||
        (app[key] as String).length > 512) ||
        app.keys.any((key) => key is String && key.startsWith('remuneration_') && !keys.contains(key)) ||
        app['remuneration_table_version'] != 'jp-general-2026-v1') { invalid(); }
    final kind = value['kind'];
    final health = const {'health_insurance', 'nursing_insurance', 'child_support'}.contains(kind);
    if (!health && kind != 'pension_insurance') { invalid(); }
    final uri = Uri.tryParse(app['remuneration_source_url'] as String);
    if (uri == null || uri.toString() != 'https://www.kyoukaikenpo.or.jp/lp/2026hokenryou/' ||
        uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || uri.hasPort ||
        !(health ? uri.host == 'www.kyoukaikenpo.or.jp' :
          const {'www.kyoukaikenpo.or.jp', 'www.nenkin.go.jp'}.contains(uri.host))) { invalid(); }
    final from = app['remuneration_effective_from'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(app['remuneration_document_hash'] as String) ||
        from != (health ? '2026-03-01' : '2020-09-01')) { invalid(); }
    String? verificationUrl;
    if (!health || app.containsKey('remuneration_verification_url') ||
        app.containsKey('remuneration_verification_hash')) {
      final rawUrl = app['remuneration_verification_url'];
      final hash = app['remuneration_verification_hash'];
      if (rawUrl is! String || rawUrl.length > 512 || hash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) { invalid(); }
      final verification = Uri.tryParse(rawUrl);
      if (verification == null || verification.toString() !=
          'https://www.nenkin.go.jp/service/yougo/hagyo/hyojunhoshugetsu.html' ||
          verification.scheme != 'https' ||
          verification.host != 'www.nenkin.go.jp' || verification.userInfo.isNotEmpty ||
          verification.hasPort || verification.hasQuery || verification.hasFragment) { invalid(); }
      verificationUrl = verification.toString();
    }
    List<int> csv(String key) {
      final raw = app[key] as String;
      if (!RegExp(r'^(0|[1-9][0-9]*)(,(0|[1-9][0-9]*))*$').hasMatch(raw)) { invalid(); }
      final values = raw.split(',').map(int.tryParse).toList();
      if (values.any((v) => v == null || v < 0 || v > 2147483647)) { invalid(); }
      return values.cast<int>();
    }
    final bases = csv('remuneration_bases_csv');
    final lower = csv('remuneration_lower_bounds_csv');
    final expectedBases = health ? PayrollStandardRemuneration.healthBases :
        PayrollStandardRemuneration.healthBases.sublist(3, 35);
    final expectedLower = health ? PayrollStandardRemuneration.lowerBounds :
        [0, ...PayrollStandardRemuneration.lowerBounds.sublist(4, 35)];
    if (bases.length != expectedBases.length || lower.length != expectedLower.length) { invalid(); }
    for (var i = 0; i < expectedBases.length; i++) {
      if (bases[i] != expectedBases[i] || lower[i] != expectedLower[i]) { invalid(); }
    }
    return PayrollOfficialRemunerationTable._(List.unmodifiable(bases),
        List.unmodifiable(lower), uri.toString(), app['remuneration_document_hash'] as String,
        app['remuneration_effective_from'] as String, verificationUrl);
  }
}

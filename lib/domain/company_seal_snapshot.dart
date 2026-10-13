import 'company_seal_design.dart';

/// A document's original seal choice. Missing metadata is a legacy document;
/// it never opts in to a company's newly selected style.
class CompanySealSnapshot {
  const CompanySealSnapshot._(this.style, this.name, [this.companyId]);
  static const legacy = CompanySealSnapshot._('legacy', '');
  final String style;
  final String name;
  final String? companyId;

  static CompanySealSnapshot fromJson(Object? value) {
    if (value == null) return legacy;
    if (value is! Map ||
        value['version'] != 1 ||
        (value['style'] is! String ||
            !CompanySealDesign.supported(value['style'] as String)) ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty) {
      throw StateError('The saved company seal metadata is invalid.');
    }
    final style = value['style'] as String;
    final name = value['name'] as String;
    if (CompanySealDesign.isPng(style) &&
        (value['company_id'] != CompanySealDesign.companyId ||
            name != CompanySealDesign.companyName)) {
      throw StateError('The saved PNG seal belongs to another company.');
    }
    return CompanySealSnapshot._(
      style,
      name,
      CompanySealDesign.isPng(style) ? value['company_id'] as String : null,
    );
  }

  /// Only unsaved previews may use the company's current choice. Saved
  /// documents always read their original snapshot through [fromJson].
  static CompanySealSnapshot forPreview(Map<String, dynamic> company) {
    final name = company['name']?.toString() ?? '';
    final style = company['company_seal_style']?.toString() ?? 'legacy';
    if (name.trim().isEmpty && style == 'legacy') return legacy;
    return fromJson({
      'version': 1,
      'style': style,
      'name': name,
      'company_id': company['id'],
    });
  }

  String registeredName(String legacyName) => name.isEmpty ? legacyName : name;
}

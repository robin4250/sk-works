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

  String registeredName(String legacyName) => name.isEmpty ? legacyName : name;
}

/// A document's original seal choice. Missing metadata is a legacy document;
/// it never opts in to a company's newly selected style.
class CompanySealSnapshot {
  const CompanySealSnapshot._(this.style, this.name);
  static const legacy = CompanySealSnapshot._('legacy', '');
  final String style;
  final String name;

  static CompanySealSnapshot fromJson(Object? value) {
    if (value == null) return legacy;
    if (value is! Map || value['version'] != 1 ||
        !const ['legacy', 'aoyagi_reisho'].contains(value['style']) ||
        value['name'] is! String || (value['name'] as String).trim().isEmpty) {
      throw StateError('The saved company seal metadata is invalid.');
    }
    return CompanySealSnapshot._(value['style'] as String, value['name'] as String);
  }

  String registeredName(String legacyName) => name.isEmpty ? legacyName : name;
}

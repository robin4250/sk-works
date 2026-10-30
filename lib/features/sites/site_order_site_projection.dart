/// Typed, nonfinancial directory projection for a *new package-aware* receiver.
/// This is not an authorization function and never replaces server validation.
/// Free-form order notes are deliberately excluded: a schema whitelist that
/// copies `notes` can still disclose prices written in those notes.
class SiteOrderSiteProjection {
  SiteOrderSiteProjection._(this._value);
  final Map<String,Object?> _value;
  static const fields = <String>{'source_site_id','name','formal_name','address',
    'nearest_station','representative_name','representative_phone','latitude',
    'longitude','starts_on','ends_on'};
  factory SiteOrderSiteProjection.fromSource(Map<String,dynamic> source) {
    final result=<String,Object?>{};
    for(final key in fields) {
      if(!source.containsKey(key))continue;
      final value=source[key];
      if(const {'latitude','longitude'}.contains(key)) {
        if(value!=null && (value is! num || !value.isFinite ||
          value < (key=='latitude'?-90:-180) || value > (key=='latitude'?90:180))) {
          throw FormatException('現場の位置情報を確認できません。');
        }
      } else if(value!=null && (value is! String || value.length>1024)) {
        throw FormatException('現場の基本情報を確認できません。');
      }
      result[key]=value;
    }
    if(result['source_site_id'] is! String || (result['source_site_id'] as String).trim().isEmpty ||
      result['name'] is! String || (result['name'] as String).trim().isEmpty) {
      throw FormatException('共有元の現場を確認できません。');
    }
    // Receiving a package does not silently mark a site as in progress.
    result['status']='preparation';
    return SiteOrderSiteProjection._(Map.unmodifiable(result));
  }
  Map<String,Object?> toJson()=>Map.of(_value);
}

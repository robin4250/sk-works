import 'company_seal_design.dart';
import 'company_uploaded_seal_png.dart';

/// A document's original seal choice. Missing metadata is a legacy document;
/// it never opts in to a company's newly selected style.
class CompanySealSnapshot {
  const CompanySealSnapshot._(this.style, this.name, [this.companyId, this.uploadedPng, this.pngVersionId]);
  static const legacy = CompanySealSnapshot._('legacy', '');
  final String style;
  final String name;
  final String? companyId;
  final CompanyUploadedSealPng? uploadedPng;
  final String? pngVersionId;
  static const uploadedStyle = 'uploaded_png';

  static CompanySealSnapshot fromJson(Object? value) {
    if (value == null) return legacy;
    if (value is Map && value['version'] == 2) {
      final uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      if (value['style'] != uploadedStyle || value['name'] is! String ||
          (value['name'] as String).trim().isEmpty ||
          value['company_id'] is! String || !uuid.hasMatch(value['company_id'] as String) ||
          value['png_version_id'] is! String || !uuid.hasMatch(value['png_version_id'] as String) ||
          value['png_base64'] is! String || value['png_sha256'] is! String) {
        throw StateError('The saved uploaded seal metadata is invalid.');
      }
      final png = CompanyUploadedSealPng.fromBase64(value['png_base64'] as String,
          expectedSha256: value['png_sha256'] as String);
      return CompanySealSnapshot._(uploadedStyle, value['name'] as String,
          value['company_id'] as String, png, value['png_version_id'] as String);
    }
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
    final uploaded = company['company_seal_uploaded_snapshot'];
    if (uploaded != null) {
      final snapshot = fromJson(uploaded);
      if (snapshot.companyId != company['id'] || snapshot.name != company['name'] || snapshot.uploadedPng == null) {
        throw StateError('The current PNG seal belongs to another company.');
      }
      return snapshot;
    }
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


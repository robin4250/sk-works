// Internal server subprocess. stdin must come from the private render job,
// never a public upload. It has no DB credentials or network operations.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// The standalone package intentionally reuses app source without Flutter SDK dependencies.
// ignore: avoid_relative_lib_imports
import '../lib/domain/company_seal_snapshot.dart';
// The standalone package intentionally reuses app source without Flutter SDK dependencies.
// ignore: avoid_relative_lib_imports
import '../lib/domain/trade_document_terms_snapshot.dart';
// The standalone package intentionally reuses app source without Flutter SDK dependencies.
// ignore: avoid_relative_lib_imports
import '../lib/features/shared/company_pdf_assets_io.dart';
// The standalone package intentionally reuses app source without Flutter SDK dependencies.
// ignore: avoid_relative_lib_imports
import '../lib/features/shared/trade_document_form_renderer.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw StateError('Canonical asset root required.');
    }
    configureCanonicalPdfAssets(arguments.single);
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stdin) {
      if (buffer.length + chunk.length > 2 * 1024 * 1024) {
        throw StateError('Canonical evidence too large.');
      }
      buffer.add(chunk);
    }
    final raw = jsonDecode(utf8.decode(buffer.takeBytes()));
    if (raw is! Map ||
        raw['body'] is! Map ||
        raw['seals'] is! List ||
        (raw['seals'] as List).length != 1 ||
        raw['consents'] is! List ||
        (raw['consents'] as List).length != 1 ||
        !RegExp(r'^[a-f0-9]{64}$')
            .hasMatch(raw['render_hash']?.toString() ?? '')) {
      throw StateError('Exact approved evidence required.');
    }
    final body = Map<String, dynamic>.from(raw['body'] as Map);
    final seal = (raw['seals'] as List).single;
    final consent = (raw['consents'] as List).single;
    final issuer = body['issuer_company_id'];
    if (issuer is! String ||
        issuer == body['counterparty_company_id'] ||
        seal is! Map ||
        consent is! Map ||
        seal['company_id'] != issuer ||
        consent['company_id'] != issuer ||
        raw['render_seal_company_id'] != issuer ||
        seal['seal_hash'] != consent['seal_hash'] ||
        seal['version_key'] != consent['version_key'] ||
        body.containsKey('company_seal_snapshot') ||
        body.containsKey('company_seal_enabled')) {
      throw StateError('Issuer seal binding required.');
    }
    TradeDocumentTermsSnapshot.fromJson(body['contract_terms']);
    final snapshot = CompanySealSnapshot.fromJson(seal['seal_snapshot']);
    if (snapshot.registeredName('') != (body['issuer'] as Map?)?['name']) {
      throw StateError('Approved issuer name mismatch.');
    }
    final payload = <String, dynamic>{
      ...body,
      'company_seal_snapshot': seal['seal_snapshot'],
      'company_seal_enabled': true,
    };
    final bytes = await TradeDocumentFormRenderer.canonical(payload);
    if (bytes.length > 20 * 1024 * 1024) {
      throw StateError('Canonical PDF too large.');
    }
    stdout.add(bytes);
    await stdout.flush();
  } catch (_) {
    // No evidence, personal data, stamp bytes or filesystem details in logs.
    stderr.writeln('canonical_render_rejected');
    exitCode = 1;
  }
}

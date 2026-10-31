import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> envelope() {
    final cases = jsonDecode(
      File('tool/canonical_renderer/synthetic-cases.json').readAsStringSync(),
    ) as Map;
    final evidence = cases.values.first as Map;
    final seal = Map<String, dynamic>.from((evidence['seals'] as List).single);
    return {
      'purpose': 'unsigned_review',
      'preview_only': true,
      'can_register': false,
      'can_send': false,
      'preview_id': '10000000-0000-4000-8000-000000000001',
      'operation_id': '10000000-0000-4000-8000-000000000002',
      'document_id': '10000000-0000-4000-8000-000000000003',
      'revision': 1,
      'body_hash': 'a' * 64,
      'source_hash': 'b' * 64,
      'seal_hash': seal['seal_hash'],
      'renderer_contract': SiteOrderOutgoingConsentPreview.rendererContract,
      'body': evidence['body'],
      'own_seal': seal,
    };
  }

  test('preview rejects consent evidence and sendable capabilities', () {
    for (final change in <Map<String, dynamic>>[
      {'consents': []},
      {'can_send': true},
      {'can_register': true},
      {'preview_only': false},
      {'purpose': 'approved'},
      {'revision': 2},
      {'renderer_contract': 'unknown'},
      {'body_hash': 'invalid'},
    ]) {
      expect(
        () => SiteOrderOutgoingConsentPreview.fromServerEnvelope({
          ...envelope(),
          ...change,
        }),
        throwsFormatException,
      );
    }
  });

  test('preview uses adopted canvas and detaches caller stamp data', () async {
    final input = envelope();
    final preview = SiteOrderOutgoingConsentPreview.fromServerEnvelope(input);
    (input['body'] as Map).clear();
    (input['own_seal'] as Map).clear();
    final pdf = await preview.render();
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    expect(pdf.length, greaterThan(10000));
  });
}

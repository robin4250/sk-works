import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same immutable body and seal render through the actual app bundle',
    () async {
      final cases = jsonDecode(
        await File('tool/canonical_renderer/synthetic-cases.json')
            .readAsString(),
      ) as Map;
      final output = Platform.environment['SKO_CANONICAL_PDF_OUTPUT_DIR'];
      if (output != null) {
        await Directory(output).create(recursive: true);
      }
      for (final entry in cases.entries) {
        final evidence = entry.value as Map;
        final payload = Map<String, dynamic>.from(evidence['body'] as Map);
        final original = jsonEncode(payload);
        payload['company_seal_snapshot'] =
            (evidence['seals'] as List).single['seal_snapshot'];
        payload['company_seal_enabled'] = true;
        final bytes = await TradeDocumentFormRenderer.canonical(payload);
        expect(bytes.length, greaterThan(10000));
        if (output != null) {
          await File('$output/app-${entry.key}.pdf').writeAsBytes(bytes);
        }
        payload.remove('company_seal_snapshot');
        payload.remove('company_seal_enabled');
        expect(jsonEncode(payload), original);
      }
    },
  );
}

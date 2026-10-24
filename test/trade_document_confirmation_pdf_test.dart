import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_approved_pdf.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_model.dart';

String _grouped(int amount) {
  final value = amount.toString();
  return [for (var i = 0; i < value.length; i++)
    '${i > 0 && (value.length - i) % 3 == 0 ? ',' : ''}${value[i]}'].join();
}

/// Uses the real approved renderer and its real asset font. No mocked font,
/// invented seal, injected attachment or standalone-source substitution.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real SQL approved evidence produces both companies PDFs with the registered immutable stamp', () async {
    final source = File('test/fixtures/trade_document_confirmation_api_synthetic.json');
    final sourceBytes = source.readAsBytesSync();
    final sql = jsonDecode(utf8.decode(sourceBytes)) as Map;
    expect(sql['synthetic_fixture'], true);
    final output = Platform.environment['SKO_TRADE_CONFIRMATION_PDF_OUTPUT_DIR'];
    final directory = output == null ? null : Directory(output);
    directory?.createSync(recursive: true);
    final manifest = <Map<String, dynamic>>[];
    final payloads = <String, List<Map<String, dynamic>>>{};
    var pngCases = 0;
    const renders = {
      'order-issued': 'issued_render', 'order-received': 'received_render',
      'acceptance-issued': 'invoice_render', 'acceptance-received': 'invoice_received_render',
    };
    for (final entry in renders.entries) {
      expect(sql.containsKey(entry.value), true, reason: 'Actual SQL export must include ${entry.value}; no fabricated render response.');
      final raw = Map<String, dynamic>.from(sql[entry.value] as Map);
      final original = jsonEncode(raw);
      final scope = tradeConfirmationRenderScope(raw);
      final attachment = TradeConfirmationPdf.approvedAttachment(raw, scope, raw['actor_id'] as String);
      final body = (raw['evidence'] as Map)['body'] as Map;
      final issuer = body['issuer'] as Map, counterparty = body['counterparty'] as Map;
      final kind = raw['kind'] as String;
      final seal = CompanySealSnapshot.fromJson(attachment.payload['company_seal_snapshot']);
      final bytes = await TradeConfirmationPdf.approved(raw, scope, raw['actor_id'] as String);
      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(Uint8List.sublistView(bytes, 0, 5)), '%PDF-');
      expect(jsonEncode(raw), original);
      expect(seal.name, issuer['name']);
      expect(attachment.payload['total_amount_yen'], body['total_amount_yen']);
      expect(attachment.payload['tax_amount_yen'], body['tax_amount_yen']);
      (payloads[kind] ??= []).add(attachment.payload);
      final issue = DateTime.parse(body['issue_date'] as String);
      final expectedTexts = <String>[
        kind == 'invoice' ? '注文請書' : '注文書',
        '${body['month']} 月分',
        for (final party in [issuer, counterparty])
          for (final field in ['name', 'address', 'corporate_number', 'representative_name'])
            if (party[field] is String && (party[field] as String).isNotEmpty) party[field] as String,
        if (body['work_name'] is String && (body['work_name'] as String).isNotEmpty) body['work_name'] as String,
        if (body['work_address'] is String && (body['work_address'] as String).isNotEmpty) body['work_address'] as String,
        if (kind == 'invoice') '${issue.year}年${issue.month}月${issue.day}日' else body['issue_date'] as String,
        if (kind == 'payment_certificate') ...[
          _grouped(body['total_amount_yen'] as int), _grouped(body['tax_amount_yen'] as int),
        ],
      ];
      final png = seal.uploadedPng;
      if (png != null) {
        pngCases++;
        expect(sha256.convert(png.bytes).toString(), png.sha256);
        if (directory != null) {
          File('${directory.path}/${entry.key}-registered-seal.png').writeAsBytesSync(png.bytes);
        }
      }
      if (directory != null) {
        File('${directory.path}/${entry.key}.pdf').writeAsBytesSync(bytes);
      }
      manifest.add({
        'file': '${entry.key}.pdf', 'kind': kind, 'side': raw['side'], 'archive': false,
        'document_id': raw['document_id'], 'local_document_id': raw['local_document_id'],
        'document_revision': raw['document_revision'], 'body_hash': (raw['evidence'] as Map)['body_hash'],
        'expected_pages': 1, 'expected_texts': expectedTexts, 'pdf_sha256': sha256.convert(bytes).toString(),
        'issuer_name': issuer['name'], 'counterparty_name': counterparty['name'],
        'total_amount_yen': body['total_amount_yen'], 'tax_amount_yen': body['tax_amount_yen'],
        'amount_fields_visible': kind == 'payment_certificate',
        'seal_style': seal.style, 'renderer_contract': tradeConfirmationRendererContract,
        'registered_png_file': png == null ? null : '${entry.key}-registered-seal.png',
        'registered_png_sha256': png?.sha256, 'registered_png_width': png?.width, 'registered_png_height': png?.height,
      });
    }
    expect(pngCases, greaterThanOrEqualTo(2));
    for (final pair in payloads.values) {
      expect(pair.length, 2);
      expect(pair.first, pair.last);
    }
    for (final kind in ['invoice', 'payment_certificate']) {
      final pair = manifest.where((item) => item['kind'] == kind).toList();
      expect(pair[0]['document_id'], pair[1]['document_id']);
      expect(pair[0]['local_document_id'], isNot(pair[1]['local_document_id']));
    }
    if (directory != null) {
      File('${directory.path}/manifest.json').writeAsStringSync(jsonEncode({
        'schema': 1, 'synthetic_fixture': true, 'fixture_sha256': sha256.convert(sourceBytes).toString(), 'files': manifest,
      }));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/features/sites/site_order_outgoing_body_factory.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';

String _id(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
SiteOrderPendingPrepare _pending() => SiteOrderPendingPrepare(
  siteId: _id(3),
  documentId: _id(5),
  localId: _id(6),
  tradeId: _id(7),
  requestId: _id(8),
  sessionId: _id(4),
);
Map<String, dynamic> _context() => {
  'contract_version': 1,
  'actor_id': _id(1),
  'session_id': _id(4),
  'company_id': _id(2),
  'site_id': _id(3),
  'trade_company_id': _id(7),
  'counterparty_company_id': _id(9),
  'connection_fingerprint': 'a' * 64,
  'creates_document': false,
  'records_consent': false,
  'can_send': false,
  'issuer': {
    'name': '合成甲会社',
    'address': '合成甲住所',
    'representative_name': '合成甲代表',
    'corporate_number': '',
    'phone': '000',
    'fax': '001',
  },
  'counterparty': {
    'name': '合成乙会社',
    'address': '合成乙住所',
    'representative_name': '合成乙代表',
    'corporate_number': '',
    'phone': '002',
  },
  'site': <String, dynamic>{
    'name': '合成工事',
    'address': '合成現場住所',
    'period_start': '2026-10-01',
    'period_end': '2026-10-31',
  },
  'own_seal': {
    'snapshot': {'version': 1, 'style': 'legacy', 'name': '合成甲会社'},
    'seal_hash': 'b' * 64,
    'version_id': null,
    'asset_hash': null,
    'version_key': 'synthetic',
    'renderer_contract': 'synthetic',
  },
};
SiteOrderOutgoingBodyFactory _factory({
  Map<String, dynamic>? context,
  Map<String, dynamic>? terms,
}) => SiteOrderOutgoingBodyFactory(
  verifiedContext: context ?? _context(),
  actorId: _id(1),
  companyId: _id(2),
  pending: _pending(),
  termsSnapshot: terms ?? TradeDocumentTermsSnapshot.reference,
);

void main() {
  test('registered PNG asset is checked separately from canonical body budget', () {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
    final original = base64Decode(png), bytes = Uint8List(1048576);
    final offset = original.length - 12,
        paddingLength = bytes.length - original.length - 12;
    bytes.setRange(0, offset, original);
    final data = ByteData.sublistView(bytes)..setUint32(offset, paddingLength);
    bytes.setRange(offset + 4, offset + 8, const [118, 112, 65, 103]);
    data.setUint32(offset + 8 + paddingLength, 0xe2d78d2b);
    bytes.setRange(bytes.length - 12, bytes.length, original.sublist(offset));
    final context = _context();
    (context['own_seal'] as Map)['snapshot'] = {
      'version': 2,
      'style': 'uploaded_png',
      'name': '合成甲会社',
      'company_id': _id(2),
      'png_version_id': _id(10),
      'png_base64': base64Encode(bytes),
      'png_sha256':
          '5f92af7cdc287da4dda4728edb9910da2cbd16d1ed336d99e8532662c1f60f8b',
    };
    final factory = _factory(context: context),
        draft = factory.newEditor(issueDate: '2026-10-31').withChanges({
          'total_amount_yen': 120,
          'tax_amount_yen': 20,
        });
    expect(jsonEncode(draft.payload).length, greaterThan(16384));
    final canonical = factory.canonicalForPrepare(draft);
    expect(jsonEncode(canonical).length, lessThan(16384));
    expect(canonical.containsKey('company_seal_snapshot'), false);
  });
  test('new editor reuses adopted defaults and never fabricates money', () {
    final factory = _factory(),
        draft = factory.newEditor(issueDate: '2026-10-31'),
        body = draft.payload;
    expect(body['total_amount_yen'], isNull);
    expect(body['tax_amount_yen'], isNull);
    final form = body['form_fields'] as Map;
    expect(form['work_content'], 'とび工事');
    expect(form['progress_cutoff_day'], 'month_end');
    expect(form['payment_month_offset'], 2);
    expect(form['payment_day'], 5);
    expect(form['supplies'], '仮設材他');
    expect((form['rows'] as List).first['unit_price_yen'], isNull);
    expect(body['notes'], tradeDocumentDefaultNotes);
    expect(() => factory.canonicalForPrepare(draft), throwsFormatException);
  });
  test('canonical candidate strips editor-only seal and retains pinned terms and exact parties', () {
    final factory = _factory(),
        draft = factory.newEditor(issueDate: '2026-10-31').withChanges({
          'total_amount_yen': 120,
          'tax_amount_yen': 20,
        });
    final body = factory.canonicalForPrepare(draft);
    expect(body.containsKey('company_seal_snapshot'), false);
    expect(body.containsKey('company_seal_enabled'), false);
    expect(body['contract_terms'], TradeDocumentTermsSnapshot.reference);
    expect(body['issuer'], _context()['issuer']);
    expect(body['counterparty'], _context()['counterparty']);
    expect(body['transaction_id'], _id(5));
    expect(body['total_amount_yen'], 120);
    expect((draft.payload['company_seal_snapshot'] as Map)['name'], '合成甲会社');
  });
  test(
    'prepared explicit blanks and payment conditions never get new defaults',
    () {
      final factory = _factory(),
          draft = factory.newEditor(issueDate: '2026-10-31').withChanges({
            'total_amount_yen': 120,
            'tax_amount_yen': 20,
            'notes': '',
            'payment_conditions': '保存済み条件',
          });
      final canonical = factory.canonicalForPrepare(draft);
      final form = TradeDocumentFormFields.empty().toJson();
      canonical['form_fields'] = form;
      final reopened = factory.editorForPreparedBody(canonical);
      expect(reopened.payload['notes'], '');
      expect(reopened.payload['payment_conditions'], '保存済み条件');
      expect(reopened.payload['form_fields'], form);
      expect(canonical.containsKey('company_seal_snapshot'), false);
    },
  );
  test('party object key order does not change canonical identity', () {
    final factory = _factory(),
        draft = factory.newEditor(issueDate: '2026-10-31').withChanges({
          'total_amount_yen': 120,
          'tax_amount_yen': 20,
        });
    final body = factory.canonicalForPrepare(draft),
        party = body['issuer'] as Map;
    body['issuer'] = {
      for (final key in party.keys.toList().reversed) key: party[key],
    };
    expect(
      factory.canonicalForPrepare(
        factory.editorForPreparedBody(body),
      )['issuer'],
      party,
    );
  });
  test('missing periods remain blank and prevent preparation', () {
    final context = _context();
    (context['site'] as Map)['period_start'] = null;
    final factory = _factory(context: context),
        draft = factory.newEditor(issueDate: '2026-10-31').withChanges({
          'total_amount_yen': 120,
          'tax_amount_yen': 20,
        });
    expect(draft.payload['period_start'], '');
    expect(() => factory.canonicalForPrepare(draft), throwsFormatException);
  });
  for (final key in [
    'actor_id',
    'session_id',
    'company_id',
    'site_id',
    'trade_company_id',
  ]) {
    test('changed $key cannot construct a source-bound factory', () {
      final context = _context()..[key] = _id(99);
      expect(() => _factory(context: context), throwsStateError);
    });
  }
  test('unknown terms are rejected rather than overwritten or upgraded', () {
    expect(
      () => _factory(
        terms: {...TradeDocumentTermsSnapshot.reference, 'version': 2},
      ),
      throwsFormatException,
    );
    final factory = _factory(),
        body = factory.canonicalForPrepare(
          factory.newEditor(issueDate: '2026-10-31').withChanges({
            'total_amount_yen': 120,
            'tax_amount_yen': 20,
          }),
        );
    body['contract_terms'] = {
      ...TradeDocumentTermsSnapshot.reference,
      'source_sha256': 'c' * 64,
    };
    expect(() => factory.editorForPreparedBody(body), throwsFormatException);
  });
  test('received direction and foreign seal cannot be reinterpreted as own new order', () {
    final factory = _factory(),
        draft = factory.newEditor(issueDate: '2026-10-31').withChanges({
          'total_amount_yen': 120,
          'tax_amount_yen': 20,
        });
    final body = factory.canonicalForPrepare(draft)
      ..['issuer_company_id'] = _id(9);
    expect(() => factory.editorForPreparedBody(body), throwsStateError);
    final context = _context();
    (context['own_seal'] as Map)['snapshot'] = {
      'version': 1,
      'style': 'legacy',
      'name': '合成乙会社',
    };
    expect(() => _factory(context: context), throwsStateError);
  });
}

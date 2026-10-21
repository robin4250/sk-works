import 'package:sk_works/domain/company_uploaded_seal_png.dart';
import 'package:sk_works/domain/company_seal_design.dart';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_resolver.dart';

void main() {
  Map<String, dynamic> workspace() => {
    'source_locked': false,
    'source_blocked': false,
    'source_changed': false,
    'attachment': null,
    'defaults': {
      'version': 1,
      'kind': 'acceptance',
      'month': '2026-01',
      'issuer': {'name': '受注会社'},
      'counterparty': {'name': '発注会社'},
      'company_seal_snapshot': {
        'version': 1,
        'style': 'legacy',
        'name': '受注会社',
      },
      'company_seal_enabled': false,
      'total_amount_yen': 110000,
    },
    'template': <String, dynamic>{
      'acceptance_text': '{order_date}の注文を承諾',
      'issuer': {'name': '別会社'},
      'total_amount_yen': 1,
    },
  };
  final date = DateTime(2026, 2, 5);

  test(
    'unsaved draft uses authorized source and prose without mutating input',
    () {
      final data = workspace();
      var reported = 0;
      final result = InvoiceAcceptanceResolver.resolve(data, issueDate: date,
        onMissingLockedAcceptance: () { reported++; })!;
      expect(reported, 0);
      expect(result.payload['order_date'], '2025-12-15');
      expect(result.payload['issue_date'], '2026-02-05');
      expect(result.payload['acceptance_text'], '2025-12-15の注文を承諾');
      expect(result.payload['issuer'], {'name': '受注会社'});
      expect(result.payload['total_amount_yen'], 110000);
      expect((data['defaults'] as Map).containsKey('issue_date'), false);
      expect(data['attachment'], isNull);
    },
  );
  test('saved appendix wins over current template and issue date', () {
    final data = workspace();
    final saved = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    data['source_locked'] = true;
    var reported = 0;
    final result = InvoiceAcceptanceResolver.resolve(data, issueDate: null,
      onMissingLockedAcceptance: () { reported++; })!;
    expect(reported, 0);
    expect(result.version, 7);
    expect(result.payload, saved.payload);
  });
  test('locked missing acceptance is generated without saving or a manual notice', () {
    final data = workspace()..['source_locked'] = true;
    final parent = CompanySealSnapshot.fromJson({
      'version': 1, 'style': 'legacy', 'name': '親請求書の固定印',
    });
    var reported = 0;
    final result = InvoiceAcceptanceResolver.resolve(data, issueDate: date,
      parentSealSnapshot: parent, parentSealEnabled: true,
      onMissingLockedAcceptance: () { reported++; })!;
    expect(reported, 0);
    expect(result.payload['issue_date'], '2026-02-05');
    expect(result.payload['company_seal_snapshot'], {
      'version': 1, 'style': 'legacy', 'name': '親請求書の固定印',
    });
    expect(result.payload['company_seal_enabled'], true);
    expect((data['defaults'] as Map)['company_seal_snapshot'], {
      'version': 1, 'style': 'legacy', 'name': '受注会社',
    });
    expect(data['source_locked'], true);
    expect(data['attachment'], isNull);
  });
  test('locked parent with unknown seal or issue date cannot use current-company seal', () {
    final data = workspace()..['source_locked'] = true;
    expect(() => InvoiceAcceptanceResolver.resolve(data, issueDate: date), throwsStateError);
    expect(() => InvoiceAcceptanceResolver.resolve(data, issueDate: null,
      parentSealSnapshot: CompanySealSnapshot.legacy, parentSealEnabled: true), throwsStateError);
    final legacy = InvoiceAcceptanceResolver.resolve(data, issueDate: date,
      parentSealSnapshot: CompanySealSnapshot.legacy, parentSealEnabled: false)!;
    expect(legacy.payload['company_seal_snapshot'], isNull);
    expect(legacy.payload['company_seal_enabled'], false);
  });
  test('changed source and unknown readiness cannot silently generate', () {
    for (final key in ['source_changed', 'source_blocked']) {
      final data = workspace()..[key] = true;
      expect(
        () => InvoiceAcceptanceResolver.resolve(data, issueDate: date),
        throwsStateError,
      );
    }
    for (final key in ['source_locked', 'source_blocked', 'source_changed']) {
      final unknown = workspace()..remove(key);
      expect(() => InvoiceAcceptanceResolver.resolve(unknown, issueDate: date), throwsStateError);
    }
    final data = workspace()..remove('source_locked');
    expect(
      () => InvoiceAcceptanceResolver.resolve(data, issueDate: date),
      throwsStateError,
    );
    expect(
      () => InvoiceAcceptanceResolver.resolve(workspace(), issueDate: null),
      throwsStateError,
    );
  });
  test('automatic OFF preserves saved appendices and suppresses only a new one', () {
    final data = workspace();
    final saved = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
    data['source_locked'] = true;
    data['template'] = {'auto_generate': false};
    expect(InvoiceAcceptanceResolver.resolve(data, issueDate: date), isNull);
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    final retained = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
    expect(retained.version, 7);
    expect(retained.payload, saved.payload);
  });

  test('initial construction name and location are copied to acceptance only before saving', () {
    final data = workspace();
    (data['template'] as Map).addAll(<String, dynamic>{'work_name': '同じ初期文', 'work_address': '同じ工事場所'});
    final value = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
    expect(value.payload['work_name'], '同じ初期文');
    expect(value.payload['work_address'], '同じ工事場所');
  });

  test('read-only workspace auto flag suppresses only unsaved generation without prose access', () {
    final data = workspace();
    final saved = InvoiceAcceptanceResolver.resolve(data, issueDate: date)!;
    data['template'] = <String, dynamic>{}; data['auto_generate'] = false;
    expect(InvoiceAcceptanceResolver.resolve(data, issueDate: date), isNull);
    data['attachment'] = {'version': 7, 'payload': saved.payload};
    expect(InvoiceAcceptanceResolver.resolve(data, issueDate: date)!.version, 7);
  });

  test('unknown automatic setting is rejected rather than treated as enabled', () {
    final data = workspace()..['auto_generate'] = 'true';
    expect(() => InvoiceAcceptanceResolver.resolve(data, issueDate: date), throwsStateError);
  });

  test('fixed registered PNG keeps its style and first-page OFF flag', () {
    final seal = {
      'version': 1, 'style': 'png_sumida_v1_worn',
      'name': CompanySealDesign.companyName, 'company_id': CompanySealDesign.companyId,
    };
    final data = workspace()
      ..['source_locked'] = true
      ..['company_id'] = CompanySealDesign.companyId;
    final result = InvoiceAcceptanceResolver.resolve(data, issueDate: date,
      parentSealSnapshot: CompanySealSnapshot.fromJson(seal), parentSealEnabled: false)!;
    expect(result.payload['company_seal_snapshot'], seal);
    expect(result.payload['company_seal_enabled'], false);
    expect((data['defaults'] as Map)['company_seal_enabled'], false);
  });

  test('uploaded parent seal bytes/version/company are retained; foreign company is refused', () {
    final png = CompanyUploadedSealPng.fromBase64('iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAK0lEQVR4nO3OIQEAAAwEoetfeovxBoGnq1tKQEBAQEBAQEBAQEBAQEBgHXhUDfhqRFDd3gAAAABJRU5ErkJggg==');
    const company = '11111111-1111-4111-8111-111111111111';
    final seal = {
      'version': 2, 'style': 'uploaded_png', 'name': '親の保存済み角印',
      'company_id': company, 'png_version_id': '22222222-2222-4222-8222-222222222222',
      'png_base64': png.base64, 'png_sha256': png.sha256,
    };
    final data = workspace()
      ..['source_locked'] = true
      ..['company_id'] = company;
    final parent = CompanySealSnapshot.fromJson(seal);
    final result = InvoiceAcceptanceResolver.resolve(data, issueDate: date,
      parentSealSnapshot: parent, parentSealEnabled: true)!;
    expect(result.payload['company_seal_snapshot'], seal);
    data['company_id'] = '33333333-3333-4333-8333-333333333333';
    expect(() => InvoiceAcceptanceResolver.resolve(data, issueDate: date,
      parentSealSnapshot: parent, parentSealEnabled: true), throwsStateError);
  });

}



import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '11111111-1111-1111-1111-111111111111';
const _company = '22222222-2222-2222-2222-222222222222';
const _doc = '33333333-3333-3333-3333-333333333333';
const _partner = '44444444-4444-4444-4444-444444444444';
const _claim = '55555555-5555-5555-5555-555555555555';
Map<String, dynamic> _envelope() => {
  'version': 2,
  'contract': 'expense_cost_direction',
  'document_kind': 'paymentCertificate',
  'direction': 'deduction',
  'company_id': _company,
  'document_id': _doc,
  'subject_id': _partner,
  'month': '2026-10',
  'document_revision': 3,
  'amount_yen': 1000,
  'claims': [
    {'id': _claim, 'revision': 2, 'amount_yen': 1000},
  ],
};
Map<String, dynamic> _basis(int gross) => {
  'company_id': _company,
  'document_id': _doc,
  'subject_id': _partner,
  'month': '2026-10',
  'document_revision': 3,
  'gross_before_expense_yen': gross,
  'other_deductions_yen': 0,
};

class _Fixture {
  _Fixture({this.v2 = true, this.gross = 0});
  final bool v2;
  final int gross;
  final calls = <http.Request>[];
  Map<String, dynamic>? capOverride;
  bool capabilityMissing = false;
  bool capabilityNetworkFailure = false;
  void Function(Map<String, dynamic>)? changeRow;
  void Function(Map<String, dynamic>)? changeDetails;
  late SupabaseClient client;
  String authActor = _actor;
  bool switchActorDuringDetails = false;
  Map<String, dynamic> capability() =>
      capOverride ??
      {
        'version': 1,
        'contract': 'expense_payment_direction_v2',
        'company_id': _company,
        'actor_id': _actor,
        'document_kind': 'paymentCertificate',
        'max_source_version': 2,
        'read_enabled': true,
      };
  Map<String, dynamic> row() {
    final value = <String, dynamic>{
      'id': _doc,
      'company_id': _company,
      'partner_company_id': _partner,
      'period_start': '2026-10-01',
      'period_end': '2026-10-31',
      'revision': 3,
      'gross_amount': v2 ? gross : gross + 1000,
      'deductions': v2 ? 1000 : 0,
      'net_amount': v2 ? gross - 1000 : gross + 1000,
      'status': 'draft',
      'partner_companies': {'name': '検証下請け'},
      'snapshot': v2
          ? {
              'expense_cost_direction_v2': _envelope(),
              'expense_cost_basis': _basis(gross),
            }
          : {
              'expense_extra_source_version': 1,
              'expense_extra_amount_yen': 1000,
              'expense_extra_claims': [
                {'id': _claim, 'revision': 2, 'amount_yen': 1000},
              ],
            },
    };
    changeRow?.call(value);
    return value;
  }

  Map<String, dynamic> details() {
    final value = <String, dynamic>{
      'kind': 'paymentCertificate',
      'document_id': _doc,
      'company_id': _company,
      'subject_id': _partner,
      'month': '2026-10-01',
      'revision': 3,
      'cost_recovery_amount_yen': 1000,
      if (v2) 'expense_cost_direction_v2': _envelope(),
      if (v2) 'expense_cost_basis': _basis(gross),
      'claims': [
        {
          'id': _claim,
          'company_id': _company,
          'applicant_id': _actor,
          'applicant_name': '検証社員',
          'incurred_on': '2026-10-01',
          'submitted_at': '2026-10-01T01:00:00Z',
          'description': '検証交通費',
          'amount_yen': 1000,
          'approval': 'approved',
          'revision': 2,
          'allocation': 'subcontractor',
          'counterparty_id': _partner,
          'counterparty_name': '検証下請け',
        },
      ],
    };
    changeDetails?.call(value);
    return value;
  }

  Future<void> start() async {
    client = SupabaseClient(
      'https://payment-direction.invalid',
      'synthetic-public',
      httpClient: MockClient((request) async {
        calls.add(request);
        final path = request.url.path;
        Object? body;
        if (path == '/auth/v1/token') {
          String enc(Object v) =>
              base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
          final token =
              '${enc({'alg': 'HS256', 'typ': 'JWT'})}.${enc({'sub': authActor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
          body = {
            'access_token': token,
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': authActor,
              'aud': 'authenticated',
              'role': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          };
        } else if (path == '/rest/v1/company_members') {
          body = [
            {'company_id': _company},
          ];
        } else if (path == '/rest/v1/payment_certificates') {
          body = [row()];
        } else if (path == '/rest/v1/companies') {
          body = [
            {'id': _company, 'name': '検証会社', 'company_seal_enabled': false},
          ];
        } else if (path == '/rest/v1/rpc/payment_certificate_detail_rows') {
          body = gross == 0
              ? []
              : [
                  {
                    'site_name': '検証現場',
                    'work_content': '工事代金',
                    'quantity_label': '1',
                    'unit_price_yen': gross,
                    'amount_yen': gross,
                  },
                ];
        } else if (path ==
            '/rest/v1/rpc/expense_payment_direction_capability') {
          if (capabilityNetworkFailure) throw http.ClientException('synthetic offline');
          if (capabilityMissing) {
            return http.Response(jsonEncode({'code': 'PGRST202', 'message': 'function unavailable'}), 404,
              headers: {'content-type': 'application/json'}, request: request);
          }
          body = capability();
        } else if (path == '/rest/v1/rpc/read_expense_document') {
          body = details();
          if (switchActorDuringDetails) {
            switchActorDuringDetails = false;
            authActor = _partner;
            await client.auth.signInWithPassword(
              email: 'other@example.invalid',
              password: 'synthetic',
            );
            authActor = _actor;
            await client.auth.signInWithPassword(
              email: 'fixture@example.invalid',
              password: 'synthetic',
            );
          }
        } else {
          throw StateError('Unexpected request $path');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'synthetic',
    );
    calls.clear();
  }

  Future<PaymentCertificateRecord> load({bool optIn = true}) async =>
      (await PaymentCertificateRepository.forTesting(
        client,
        enableExpenseDirectionV2: optIn,
      ).loadCertificates()).single;
  ExpenseDocumentDetails parsedDetails() => ExpenseDocumentDetails.parse(
    details(),
    ExpenseDocument.paymentCertificate,
    _doc,
    DateTime(2026, 10),
    revision: 3,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('v2 source headers stay on payment requests and do not leak to a legacy reader', () async {
    final fixture = _Fixture(v2: false);
    await fixture.start();
    try {
      await PaymentCertificateRepository.forTesting(fixture.client, enableExpenseDirectionV2: true).loadCertificates();
      final paymentCalls = fixture.calls.where((r) =>
          r.url.path == '/rest/v1/payment_certificates' ||
          r.url.path == '/rest/v1/rpc/payment_certificate_detail_rows');
      expect(paymentCalls, hasLength(2));
      for (final call in paymentCalls) {
        expect(call.headers['x-sko-payment-source-version'], '2');
      }
      for (final call in fixture.calls.where((r) => !paymentCalls.contains(r))) {
        expect(call.headers.containsKey('x-sko-payment-source-version'), isFalse);
      }
      fixture.calls.clear();
      await PaymentCertificateRepository.forTesting(fixture.client).loadCertificates();
      expect(fixture.calls.every((r) => !r.headers.containsKey('x-sko-payment-source-version')), isTrue);
    } finally { await fixture.client.dispose(); }
  });

  test('v2 source header also protects the scoped expense detail RPC', () async {
    final fixture = _Fixture();
    await fixture.start();
    try {
      await PaymentCertificateRepository.forTesting(fixture.client, enableExpenseDirectionV2: true).loadCertificates();
      final call = fixture.calls.singleWhere((r) => r.url.path == '/rest/v1/rpc/read_expense_document');
      expect(call.headers['x-sko-payment-source-version'], '2');
    } finally { await fixture.client.dispose(); }
  });

  test(
    'actual repository and common PDF pipeline render v2 expense-only -1000 and preserve v1 +1000',
    () async {
      final bytes = await rootBundle.load(
        'assets/fonts/company-seal/NotoSansJP-Bold.ttf',
      );
      for (final data in [
        (true, 0, 'v2_expense_only'),
        (true, 20000, 'v2_with_work'),
        (false, 0, 'v1_preserved'),
      ]) {
        final fixture = _Fixture(v2: data.$1, gross: data.$2);
        await fixture.start();
        try {
          final record = await fixture.load(optIn: data.$1);
          expect(record.expenseLineDeltaYen, data.$1 ? -1000 : 1000);
          expect(record.netAmount, data.$1 ? data.$2 - 1000 : 1000);
          final pdf = await PaymentCertificatePdfService.buildPdf(
            record,
            expenseDetails: fixture.parsedDetails(),
            regularFont: pw.Font.ttf(bytes),
            boldFont: pw.Font.ttf(bytes),
          );
          final out = Directory('build/payment-direction-consumer-proof')
            ..createSync(recursive: true);
          File('${out.path}/${data.$3}.pdf').writeAsBytesSync(pdf);
          expect(pdf.length, greaterThan(1000));
          expect(
            fixture.calls
                .where(
                  (r) => r.url.path.contains(
                    'expense_payment_direction_capability',
                  ),
                )
                .length,
            data.$1 ? 1 : 0,
          );
          expect(
            fixture.calls
                .where((r) => r.url.path.contains('read_expense_document'))
                .length,
            data.$1 ? 1 : 0,
          );
          expect(
            fixture.calls
                .where((r) => r.url.path == '/rest/v1/payment_certificates')
                .single
                .url
                .queryParameters['company_id'],
            'eq.$_company',
          );
        } finally {
          await fixture.client.dispose();
        }
      }
    },
  );
  test('opted-in screen reader preserves legacy amounts when capability is absent or disabled', () async {
    for (final missing in [true, false]) {
      final fixture = _Fixture(v2: false);
      fixture.capabilityMissing = missing;
      if (!missing) fixture.capOverride = fixture.capability()..['read_enabled'] = false;
      await fixture.start();
      try {
        final record = await fixture.load();
        expect(record.expenseLineDeltaYen, 1000);
        expect(record.netAmount, 1000);
        expect(fixture.calls.where((r) => r.url.path.endsWith('/expense_payment_direction_capability')), hasLength(1));
        expect(fixture.calls.where((r) => r.url.path.endsWith('/read_expense_document')), isEmpty);
        expect(fixture.calls.where((r) => !r.url.path.contains('/rpc/')).every((r) => r.method == 'GET'), isTrue);
      } finally { await fixture.client.dispose(); }
    }
  });
  test('capability network failure stops the opted-in reader before returning legacy data', () async {
    final fixture = _Fixture(v2: false)..capabilityNetworkFailure = true;
    await fixture.start();
    addTearDown(fixture.client.dispose);
    await expectLater(fixture.load(), throwsA(isA<http.ClientException>()));
    expect(fixture.calls.where((r) => r.url.path.endsWith('/payment_certificates')), isEmpty);
  });
  test('default OFF refuses v2 rather than treating it as legacy', () async {
    final fixture = _Fixture();
    await fixture.start();
    addTearDown(fixture.client.dispose);
    await expectLater(fixture.load(optIn: false), throwsStateError);
    expect(
      fixture.calls.where(
        (r) => r.url.path.contains('expense_payment_direction_capability'),
      ),
      isEmpty,
    );
  });
  test(
    'capability must match exact current actor, company, version, keys and enabled state',
    () async {
      final changes = <String, Object?>{
        'actor_id': _partner,
        'company_id': _actor,
        'version': 2,
        'read_enabled': false,
        'max_source_version': 3,
        'document_kind': 'invoice',
        'unexpected': true,
      };
      for (final entry in changes.entries) {
        final fixture = _Fixture();
        fixture.capOverride = fixture.capability()..[entry.key] = entry.value;
        await fixture.start();
        try {
          await expectLater(fixture.load(), throwsStateError);
        } finally {
          await fixture.client.dispose();
        }
      }
    },
  );
  test(
    'actual consumer rejects wrong scoped row and detail revision or signed amount',
    () async {
      for (final field in ['company_id', 'net_amount', 'revision']) {
        final fixture = _Fixture();
        fixture.changeRow = (row) {
          row[field] = field == 'company_id'
              ? _actor
              : field == 'revision'
              ? 4
              : 1000;
        };
        await fixture.start();
        try {
          await expectLater(fixture.load(), throwsStateError);
        } finally {
          await fixture.client.dispose();
        }
      }
      final fixture = _Fixture();
      fixture.changeDetails = (detail) {
        detail['revision'] = 4;
      };
      await fixture.start();
      try {
        await expectLater(fixture.load(), throwsStateError);
      } finally {
        await fixture.client.dispose();
      }
    },
  );
  test(
    'actor switch and return during expense read never exposes the stale record',
    () async {
      final fixture = _Fixture();
      await fixture.start();
      addTearDown(fixture.client.dispose);
      fixture.switchActorDuringDetails = true;
      await expectLater(fixture.load(), throwsStateError);
      expect(fixture.client.auth.currentUser?.id, _actor);
    },
  );

  test(
    'PDF refuses stale detail direction and incompatible record fields',
    () async {
      final fixture = _Fixture();
      await fixture.start();
      addTearDown(fixture.client.dispose);
      final record = await fixture.load();
      final bytes = await rootBundle.load(
        'assets/fonts/company-seal/NotoSansJP-Bold.ttf',
      );
      fixture.changeDetails = (detail) {
        detail['expense_cost_direction_v2']['document_revision'] = 4;
      };
      expect(fixture.parsedDetails, throwsStateError);
      for (final changed in [
        (1000, record.periodStart),
        (record.netAmount, DateTime(2026, 10, 2)),
      ]) {
        final altered = PaymentCertificateRecord(
          id: record.id,
          partnerCompanyName: record.partnerCompanyName,
          partnerCompanyId: record.partnerCompanyId,
          periodStart: changed.$2,
          periodEnd: record.periodEnd,
          grossAmount: record.grossAmount,
          deductions: record.deductions,
          netAmount: changed.$1,
          status: 'draft',
          revision: 3,
          payerCompanySealEnabled: false,
          directionalExpenseRead: record.directionalExpenseRead,
        );
        await expectLater(
          PaymentCertificatePdfService.buildPdf(
            altered,
            regularFont: pw.Font.ttf(bytes),
            boldFont: pw.Font.ttf(bytes),
          ),
          throwsStateError,
        );
      }
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_cloud_repository.dart';
import 'package:sk_works/features/invoices/invoice_notification_page.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _company = '10000000-0000-0000-0000-000000000001';
const _actor = '10000000-0000-0000-0000-000000000002';
const _invoice = '10000000-0000-0000-0000-000000000003';

class _Fixture {
  late HttpServer server;
  late SupabaseClient client;
  final requests = <({String method, Uri uri, List<int> body})>[];
  bool denySeal = false;
  bool denyUploadedSeal = false;
  bool frozenInvoice = false;
  bool denyPermissions = false;
  bool signedCheckoutContract = false;
  bool signOutOnContract = false;
  Object? pendingQuantity;
  Object? pendingSource;
  bool zeroAmount = false;
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_respond);
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.test',
      password: 'synthetic-password',
    );
    requests.clear();
  }

  Future<void> close() async {
    await client.dispose();
    await server.close(force: true);
  }

  Future<void> _respond(HttpRequest request) async {
    final body = await request.fold<List<int>>(
      [],
      (result, next) => result..addAll(next),
    );
    requests.add((method: request.method, uri: request.uri, body: body));
    final path = request.uri.path;
    Object? response;
    if (path == '/auth/v1/token') {
      String encode(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': _actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
      response = {
        'access_token': token,
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': _actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'fixture@example.test',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      };
    } else if (path == '/rest/v1/company_members') {
      response = [{'company_id': _company, 'role': 'owner'}];
    } else if (path == '/rest/v1/rpc/current_feature_permissions') {
      if (denyPermissions) {
        request.response.statusCode = 403;
      }
      response = denyPermissions
          ? {'code': '42501', 'message': 'unavailable permission lookup'}
          : {'can_manage_invoices': true};
    } else if (path == '/rest/v1/rpc/route_checkout_billing_contract') {
      if (signOutOnContract) await client.auth.signOut();
      if (!signedCheckoutContract) request.response.statusCode = 404;
      response = signedCheckoutContract
          ? {'contract_version': 1, 'separate_quantity_approval_required': false}
          : {'code': 'PGRST202', 'message': 'optional contract unavailable'};
    } else if (path == '/rest/v1/rpc/refresh_signed_checkout_invoices') {
      response = {'contract_version': 1, 'checked_customer_periods': 1};
    } else if (path == '/rest/v1/rpc/invoice_document_settings') {
      if (denySeal) {
        request.response.statusCode = 403;
      }
      response = denySeal
          ? {'code': '42501', 'message': 'unavailable company lookup'}
          : {'company_id': _company, 'company_name': '検証会社', 'company_seal_style': 'legacy'};
    } else if (path == '/rest/v1/rpc/company_current_uploaded_seal') {
      request.response.statusCode = denyUploadedSeal ? 403 : 404;
      response = denyUploadedSeal
          ? {'code':'42501','message':'uploaded seal permission denied'}
          : {'code':'PGRST202','message':'uploaded seal optional backend absent'};
    } else if (path == '/rest/v1/invoices') {
      response = [{
        'id': _invoice, 'customer_id': '', 'billing_period_start': '2026-09-01',
        'billing_period_end': '2026-09-30', 'subtotal': zeroAmount ? 0 : 40000, 'tax': zeroAmount ? 0 : 4000,
        'grand_total': zeroAmount ? 0 : 44000, 'detail_mode': 'consolidated_only',
        'status': frozenInvoice ? 'finalized' : 'draft', 'finalized_at': frozenInvoice ? '2026-10-01T00:00:00Z' : null, 'approval_finalized_at': null,
        'invoice_seal_frozen': frozenInvoice, 'snapshot': {
          'customer_name': '検証取引先', 'customer_address': '検証住所',
          if (pendingQuantity != null) 'route_quantity_pending': pendingQuantity,
          if (pendingSource != null) 'route_source_pending': pendingSource,
          'sites': [{'site_id': 'site-1', 'site_name': '検証現場', 'lines': [
            {'label': '通常作業', 'quantity': 2, 'unit_price': 20000, 'amount': 40000}
          ], 'subtotal': 40000}]
        }
      }];
    } else {
      response = [];
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response));
    await request.response.close();
  }
}

void main() {
  late _Fixture fixture;
  setUp(() async { fixture = _Fixture(); await fixture.start(); });
  tearDown(() async { await fixture.close(); });

  test('notification adapter reads saved invoices without refresh or approval initialization', () async {
    fixture.signedCheckoutContract = true;
    final source = SupabaseInvoiceNoticeSource(
      fixture.client, InvoiceCloudRepository.forTesting(fixture.client),
    );
    expect(source.actor, _actor);
    final rows = await source.load();
    expect(rows.single.invoiceId, _invoice);
    expect(rows.single.grandTotalYen, 44000);
    const readRpcs = {
      '/rest/v1/rpc/invoice_document_settings',
      '/rest/v1/rpc/trade_company_workspace',
      '/rest/v1/rpc/company_current_uploaded_seal',
    };
    for (final request in fixture.requests) {
      if (request.uri.path.contains('/rpc/')) {
        expect(readRpcs, contains(request.uri.path),
          reason: 'notification entry must not refresh or initialize approvals');
      } else {
        expect(request.method, 'GET', reason: request.uri.path);
      }
    }
    expect(fixture.requests.where((r) => r.uri.path.contains('refresh_signed_checkout') ||
      r.uri.path.contains('invoice_approval_status') ||
      r.uri.path.contains('route_checkout_billing_contract') ||
      r.uri.path.contains('current_feature_permissions')), isEmpty);
  });

  test('legacy saved invoice remains readable when optional permission RPC fails', () async {
    fixture.denyPermissions = true;
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    final rows = await repository.loadAll();
    expect(rows, hasLength(1));
    expect(rows.single.grandTotalYen, 44000);
    expect(rows.single.routeQuantityPending, isFalse);
    expect(rows.single.billingPeriod, '2026年9月');
    expect(await repository.canManageFinancials(), isFalse);
    expect(rows.single.outputReadinessError, isNull);
    expect(fixture.requests.any((request) => request.uri.path == '/rest/v1/companies'), isFalse);
  });

  test('unavailable current seal keeps saved invoice visible and blocks stale output', () async {
    fixture.denySeal = true;
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    final rows = await repository.loadAll();
    expect(rows, hasLength(1));
    expect(rows.single.grandTotalYen, 44000);
    expect(rows.single.outputReadinessError, contains('角印設定'));
    await expectLater(InvoicePdfService.buildPdf(rows), throwsStateError);
    fixture.denySeal = false;
    expect((await repository.loadAll()).single.outputReadinessError, isNull);
  });

  test('uploaded-seal backend denial blocks current draft output without hiding saved amounts', () async {
    fixture.denyUploadedSeal = true;
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    final row = (await repository.loadAll()).single;
    expect(row.grandTotalYen, 44000);
    expect(row.outputReadinessError, contains('角印設定'));
    await expectLater(InvoicePdfService.buildPdf([row]), throwsStateError);
    fixture.denyUploadedSeal = false;
    expect((await repository.loadAll()).single.outputReadinessError, isNull,
      reason: 'Only a missing optional backend keeps the existing company design.');
  });

  test('frozen invoices do not read a company current PNG selection', () async {
    fixture.frozenInvoice = true;
    fixture.denySeal = true;
    fixture.denyUploadedSeal = true;
    final row = (await InvoiceCloudRepository.forTesting(fixture.client).loadAll()).single;
    expect(row.outputReadinessError, isNull);
    expect(row.grandTotalYen, 44000);
    expect(fixture.requests.any((r) => r.uri.path == '/rest/v1/rpc/company_current_uploaded_seal'), isFalse);
  });

  test('saved route pending state preserves totals and clears only with source state', () async {
    fixture.zeroAmount = true;
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    for (final value in [true, 'true', false, 'false', null]) {
      fixture.pendingQuantity = value;
      final invoice = (await repository.loadAll()).single;
      expect(invoice.routeQuantityPending, value == true || value == 'true');
      expect(invoice.grandTotalYen, 0);
    }
    expect(fixture.requests.where((request) => request.method != 'GET' &&
        !request.uri.path.contains('/rpc/')).isEmpty, isTrue);
  });

  test('source-pending state is distinct from old approval state and ready zero', () async {
    fixture.zeroAmount = true;
    fixture.pendingQuantity = false;
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    for (final value in [true, 'true', false, 'false', null]) {
      fixture.pendingSource = value;
      final invoice = (await repository.loadAll()).single;
      expect(invoice.routeQuantityPending, isFalse);
      expect(invoice.routeSourcePending, value == true || value == 'true');
      expect(invoice.amountPending, value == true || value == 'true');
      expect(invoice.grandTotalYen, 0);
    }
  });
  test('authenticated refresh requires supported contract and financial permission', () async {
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    await repository.refreshSignedCheckoutInvoices();
    expect(fixture.requests.any((r) => r.uri.path.endsWith('/refresh_signed_checkout_invoices')), isFalse);
    fixture.requests.clear();
    fixture.signedCheckoutContract = true;
    await repository.refreshSignedCheckoutInvoices();
    final refresh = fixture.requests.singleWhere((r) => r.uri.path.endsWith('/refresh_signed_checkout_invoices'));
    expect(jsonDecode(utf8.decode(refresh.body)), {'p_company_id': _company});
    fixture.requests.clear();
    fixture.denyPermissions = true;
    await repository.refreshSignedCheckoutInvoices();
    expect(fixture.requests.any((r) => r.uri.path.endsWith('/route_checkout_billing_contract') || r.uri.path.endsWith('/refresh_signed_checkout_invoices')), isFalse);
  });
  test('session change while reading capability prevents the refresh write', () async {
    fixture.signedCheckoutContract = true;
    fixture.signOutOnContract = true;
    final repository = InvoiceCloudRepository.forTesting(fixture.client);
    await expectLater(repository.refreshSignedCheckoutInvoices(), throwsStateError);
    expect(fixture.requests.any((r) => r.uri.path.endsWith('/refresh_signed_checkout_invoices')), isFalse);
  });
}



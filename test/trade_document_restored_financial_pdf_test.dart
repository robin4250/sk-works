import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/auth/app_auth_logout_persistence.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';

const _url = 'http://127.0.0.1:57417';
const _key = 'synthetic-public-fixture';
const _actor = '10000000-0000-4000-8000-000000000001';
const _otherActor = '10000000-0000-4000-8000-000000000002';
const _sid = '20000000-0000-4000-8000-000000000001';
const _otherSid = '20000000-0000-4000-8000-000000000002';
const _company = '30000000-0000-4000-8000-000000000001';
const _subject = '40000000-0000-4000-8000-000000000001';
const _partner = '50000000-0000-4000-8000-000000000001';
const _revision = '2026-10-30T00:00:00.000Z';
late HttpServer _server;
late pw.Font _font;
final _requests = <({String kind, String subject, String revision, String bearer})>[];
Completer<void>? _holdWorkspace, _workspaceStarted;
String _activeToken = '';
// The widget-test binding normally replaces HTTP with a blanket 400 stub.
// Exercise the actual SDK's loopback transport, not that unrelated test stub.
class _LoopbackHttpOverrides extends HttpOverrides {}
Future<T> _withLoopbackTransport<T>(Future<T> Function() action) =>
    HttpOverrides.runWithHttpOverrides(action, _LoopbackHttpOverrides());

String _jwt(String actor, String sid) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': actor, 'session_id': sid, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.${base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '')}';
}
Map<String, dynamic> _session({String actor = _actor, String sid = _sid}) => {
  'access_token': _jwt(actor, sid), 'refresh_token': 'synthetic-refresh-only',
  'token_type': 'bearer', 'expires_in': 3600,
  'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z'},
};

Future<void> _respond(HttpRequest request) async {
  try {
    if (request.uri.path == '/auth/v1/logout') {
      expect(request.method, 'POST');
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    expect(request.uri.path, '/rest/v1/rpc/trade_document_attachment_workspace');
    expect(request.method, 'POST');
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
    final kind = body['p_kind'] as String;
    expect(kind, isIn(['invoice', 'payment_certificate']));
    expect(body['p_subject'], _subject);
    expect(body['p_source_revision'], kind == 'invoice' ? _revision : '1');
    final bearer = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    expect(bearer, 'Bearer $_activeToken');
    _requests.add((kind: kind, subject: body['p_subject'] as String,
      revision: body['p_source_revision'] as String, bearer: bearer));
    if (_workspaceStarted?.isCompleted == false) _workspaceStarted!.complete();
    await _holdWorkspace?.future;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'company_id': _company, 'attachment': null,
      'source_locked': false, 'source_blocked': false, 'source_changed': false,
      'auto_generate': false}));
    await request.response.close();
  } on IOException {
    // Auth/lifecycle retirement may abort the real HTTP request while this
    // loopback response is held. That is a transport close, not a PDF success.
    return;
  } catch (error, stack) {
    request.response.statusCode = HttpStatus.internalServerError;
    await request.response.close();
    Zone.current.handleUncaughtError(error, stack);
  }
}

ExpenseDocumentDetails _expenses(String kind) => ExpenseDocumentDetails(
  kind: kind == 'invoice' ? ExpenseDocument.invoice : ExpenseDocument.paymentCertificate,
  documentId: _subject, subjectId: _partner, month: DateTime(2026, 10),
  claims: ExpenseClaims(companyId: _company, claims: const []));

Future<Uint8List> _build(String kind) {
  // These are the actual production financial builders. In particular, do NOT
  // pass acceptanceByInvoice/orderAttachment: the real global repository and
  // its ephemeral FormSession must perform the workspace RPC before the PDF.
  if (kind == 'invoice') {
    final invoice = InvoiceEngine.calculate(customerId: _partner, invoiceId: _subject,
      documentUpdatedAt: _revision, issueDate: DateTime(2026, 9, 30),
      billingPeriod: '2026年10月', detailMode: InvoiceDetailMode.consolidatedOnly,
      sites: const [SiteInvoiceCalculation(siteId: 'synthetic-site', siteName: 'Synthetic work',
        lines: [InvoiceLine(label: 'Synthetic work', quantity: 1, unitPriceYen: 100000)])]);
    return InvoicePdfService.buildPdf([invoice], regularFont: _font, boldFont: _font,
      settings: const InvoiceSettingsData(companyName: 'Synthetic issuer', taxRate: 10,
        welfareRate: 0, templateTitle: '請求書', footerNote: '', bankName: '',
        bankBranch: '', bankAccountType: '', bankAccountNumber: '', bankAccountHolder: '',
        companySealEnabled: false),
      approvalsByInvoice: const {_subject: []},
      expenseDetailsByInvoice: {_subject: _expenses(kind)}, allowLegacyApprovalInitialization: false);
  }
  return PaymentCertificatePdfService.buildPdf(PaymentCertificateRecord(
    id: _subject, partnerCompanyId: _partner, partnerCompanyName: 'Synthetic partner',
    payerCompanyName: 'Synthetic issuer', periodStart: DateTime(2026, 10, 1),
    periodEnd: DateTime(2026, 10, 31), grossAmount: 110000, deductions: 0,
    netAmount: 110000, status: 'draft', revision: 1, payerCompanySealEnabled: false),
    regularFont: _font, boldFont: _font, expenseDetails: _expenses(kind));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SKO_RESTORED_FINANCIAL_FIXTURE')) {
    test('restored financial PDF requires synthetic loopback configuration', () {},
      skip: 'Dedicated workflow supplies synthetic compile-time settings; no production credentials.');
    return;
  }
  setUpAll(() => _withLoopbackTransport(() async {
    expect(SupabaseBackendConfig.url, _url);
    expect(SupabaseBackendConfig.publishableKey, _key);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final restored = _session();
    _activeToken = restored['access_token'] as String;
    SharedPreferences.setMockInitialValues({
      AppAuthLogoutPersistence.sdkSessionKey(_url): jsonEncode(restored),
    });
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 57417);
    _server.listen((request) { unawaited(_respond(request)); });
    // Initialize the real production adapter, including its actual initialized
    // logout persistence fence. No test gateway binding/priming or SDK login.
    await SupabaseBackend.initializeIfConfigured();
    expect(SupabaseBackend.isInitialized, isTrue);
    expect(SupabaseBackend.client.auth.currentUser?.id, _actor);
    expect(SupabaseBackend.client.auth.currentSession?.accessToken, _activeToken);
    expect(_requests, isEmpty);
    _font = await CompanySealPdf.loadFont();
    final replay = await SupabaseBackend.client.auth.onAuthStateChange.first
        .timeout(const Duration(seconds: 5));
    for (var attempt = 0; attempt < 100 &&
        identical(replay.session, SupabaseBackend.client.auth.currentSession); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final current = SupabaseBackend.client.auth.currentSession;
    expect(replay.event, AuthChangeEvent.initialSession);
    expect(identical(replay.session, current), isFalse,
      reason: 'Actual SupabaseFlutter lazy restore must reach the cached-A/current-B production shape');
    expect(jsonEncode(replay.session!.toJson()), jsonEncode(current!.toJson()));
    expect(_requests, isEmpty, reason: 'Unexpired cold restore must not issue Auth or workspace HTTP');
  }));
  tearDownAll(() async {
    if (_holdWorkspace?.isCompleted == false) _holdWorkspace!.complete();
    await Supabase.instance.dispose();
    await _server.close(force: true);
  });
  for (final kind in ['invoice', 'payment_certificate']) {
    test('restored financial $kind uses real workspace RPC and produces its PDF', () => _withLoopbackTransport(() async {
      final before = _requests.length;
      late Uint8List bytes;
      try { bytes = await _build(kind).timeout(const Duration(seconds: 15)); }
      catch (error) {
        // This marker can only be emitted after real Backend initialization and
        // at the actual financial builder, never for fixture startup failures.
        // ignore: avoid_print
        print('RESTORED_FINANCIAL_BUILDER_FAILURE:$kind:${error.runtimeType}:$error');
        rethrow;
      }
      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(_requests.length, before + 1);
      expect(_requests.last.kind, kind);
      expect(_requests.last.bearer, 'Bearer $_activeToken');
      expect(SupabaseBackend.client.auth.currentSession?.accessToken, _activeToken);
    }));
  }
  for (final mutation in ['same-actor-new-SID', 'different-actor', 'background']) {
    test('delayed financial PDF rejects $mutation before accepting workspace result', () => _withLoopbackTransport(() async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final restored = _session();
      await SupabaseBackend.client.auth.setInitialSession(jsonEncode(restored));
      _activeToken = SupabaseBackend.client.auth.currentSession!.accessToken;
      // Let this deliberate SDK restore settle before capturing a NEW scope.
      await Future<void>.delayed(Duration.zero);
      final hold = _holdWorkspace = Completer<void>();
      final started = _workspaceStarted = Completer<void>();
      final pdf = _build('payment_certificate');
      final rejected = expectLater(pdf, throwsStateError);
      try {
        await started.future.timeout(const Duration(seconds: 5));
        if (mutation == 'background') {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        } else {
          await SupabaseBackend.client.auth.setInitialSession(jsonEncode(_session(
            actor: mutation == 'different-actor' ? _otherActor : _actor, sid: _otherSid)));
        }
        hold.complete();
        await rejected;
      } finally {
        if (!hold.isCompleted) hold.complete();
        _holdWorkspace = null; _workspaceStarted = null;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    }));
  }
  test('logout intent retires delayed financial PDF before workspace completion', () => _withLoopbackTransport(() async {
    await SupabaseBackend.client.auth.setInitialSession(jsonEncode(_session()));
    _activeToken = SupabaseBackend.client.auth.currentSession!.accessToken;
    await Future<void>.delayed(Duration.zero);
    final hold = _holdWorkspace = Completer<void>();
    final started = _workspaceStarted = Completer<void>();
    final pdf = _build('payment_certificate');
    final rejected = expectLater(pdf, throwsStateError);
    try {
      await started.future.timeout(const Duration(seconds: 5));
      final gateway = AppAuthMutationGateway.forClient(SupabaseBackend.client);
      // App-owned intent is the real synchronous quarantine signal. No native
      // printing is performed by this builder-only transport regression.
      final logout = gateway.signOut();
      hold.complete();
      await rejected;
      await logout;
    } finally {
      if (!hold.isCompleted) hold.complete();
      _holdWorkspace = null; _workspaceStarted = null;
    }
  }));
}

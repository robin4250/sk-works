import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/invoices/invoice_notice_candidate_rpc.dart';
import 'package:sk_works/features/invoices/invoice_notice_approval_panel.dart';
import 'package:sk_works/features/invoices/invoice_notice_recovery_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _NativeFixtureHttp extends HttpOverrides {}

class _TraceClient extends http.BaseClient {
  _TraceClient(this.inner, this.trace);
  final http.Client inner;
  final List<Map<String, dynamic>> trace;
  @override Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Request) { trace.add({'path': request.url.path, 'body': jsonDecode(request.body)}); }
    return inner.send(request);
  }
  @override void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('actual TLS SDK and existing factory/Panel preserve authoritative open and unknown recovery', (tester) async {
    final env = Platform.environment;
    final certificate = env['SKO_INVOICE_APP_CERT'];
    expect(certificate, isNotNull);
    final tls = SecurityContext()..setTrustedCertificates(certificate!);
    http.Client connection() => IOClient(_NativeFixtureHttp().createHttpClient(tls));
    late SupabaseClient client;
    stdout.writeln('INVOICE_APP_STAGE=auth_initialization');
    await tester.runAsync(() async {
      client = SupabaseClient(SupabaseBackendConfig.url, env['SKO_INVOICE_APP_KEY']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: connection());
      await client.auth.signInWithPassword(email: env['SKO_INVOICE_APP_EMAIL']!, password: env['SKO_INVOICE_APP_PASSWORD']!);
    });
    stdout.writeln('INVOICE_APP_STAGE=authenticated');
    final notification = env['SKO_INVOICE_APP_NOTIFICATION']!, invoice = env['SKO_INVOICE_APP_INVOICE']!, revision = env['SKO_INVOICE_APP_REVISION']!;
    final trace = <Map<String, dynamic>>[];
    // A trusted fixture CA is explicit. Default trust must reject this local
    // self-signed endpoint; there is no badCertificateCallback bypass.
    final badTrust = createInvoiceNoticeCandidateController(client: client, invoiceId: invoice, sourceRevision: revision, enabled: true,
      transportClientFactory: () => IOClient(_NativeFixtureHttp().createHttpClient(SecurityContext.defaultContext)))!;
    expect(await tester.runAsync(() => badTrust.tickets.open(notification, invoiceId: invoice, sourceRevision: revision)), false);
    badTrust.dispose();
    stdout.writeln('INVOICE_APP_STAGE=bad_certificate_rejected');
    final recovery = createInvoiceNoticeCandidateController(client: client, invoiceId: invoice, sourceRevision: revision,
      enabled: true, transportClientFactory: () => _TraceClient(connection(), trace));
    expect(recovery, isNotNull);
    final controller = recovery!;
    const channel = MethodChannel('net.nfet.printing');
    const codec = StandardMethodCodec();
    var rasterCalls = 0, legacyReads = 0;
    void Function()? emitPage;
    void Function([String? error])? emitEnd;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'printingInfo') { return {'canRaster': true, 'canPrint': false, 'canShare': false}; }
      if (call.method == 'rasterPdf') {
        rasterCalls++;
        final job = (call.arguments as Map)['job'];
        emitPage = () => tester.binding.channelBuffers.push(channel.name, codec.encodeMethodCall(MethodCall('onPageRasterized',
          {'job': job, 'width': 2, 'height': 2, 'image': Uint8List.fromList(List.filled(16, 255))})), (_) {});
        emitEnd = ([String? error]) => tester.binding.channelBuffers.push(channel.name,
          codec.encodeMethodCall(MethodCall('onPageRasterEnd', {'job': job, if (error != null) 'error': error})), (_) {});
      }
      return null;
    });
    Future<void> until(bool Function() condition, String stage) async {
      final elapsed = Stopwatch()..start();
      while (!condition()) {
        if (elapsed.elapsed > const Duration(seconds: 25)) { throw StateError('invoice fixture stage: $stage'); }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        // Native I/O progresses in runAsync; the incoming route also needs
        // an animation frame with elapsed time to leave offstage layout.
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    int sent() => trace.where((row) => (row['path'] as String).endsWith('/confirm')).length;
    FilledButton approveButton() => tester.widget<FilledButton>(find.ancestor(of: find.text('承認する'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton)).first);
    try {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: InvoiceNoticeApprovalPanel(
        controller: null, recoveryController: controller, notificationId: notification, invoiceId: invoice,
        revision: revision, isApprover: true, confirmSavedApproval: () async { legacyReads++; return true; })))));
      await until(() => find.text('承認する').evaluate().isNotEmpty, 'authoritative open');
      stdout.writeln('INVOICE_APP_STAGE=authoritative_open');
      expect(approveButton().onPressed, isNull); expect(sent(), 0);
      expect(trace.first['body'], {'notification_id': notification, 'invoice_id': invoice, 'source_revision': revision});
      FilledButton previewButton() => tester.widget<FilledButton>(find.ancestor(of: find.text('表示内容と印影を確認しました'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton)).first);
      await tester.tap(find.text('注文請書と登録印影を確認')); await tester.pump();
      await until(() => find.text('表示内容と印影を確認しました').evaluate().isNotEmpty && rasterCalls == 1, 'first preview raster requested');
      stdout.writeln('INVOICE_APP_STAGE=first_raster_pending');
      expect(previewButton().onPressed, isNull);
      emitEnd!('fixture raster failure');
      await until(() => find.text('本文と印影を表示できません').evaluate().isNotEmpty, 'renderer failure');
      stdout.writeln('INVOICE_APP_STAGE=raster_error_blocked');
      expect(previewButton().onPressed, isNull); expect(sent(), 0);
      // fullscreenDialog implies CloseButton, not the pageBack BackButton.
      await tester.tap(find.byType(CloseButton)); await tester.pumpAndSettle();
      stdout.writeln('INVOICE_APP_STAGE=failed_preview_closed');
      expect(approveButton().onPressed, isNull);
      await tester.tap(find.text('注文請書と登録印影を確認')); await tester.pump();
      await until(() => rasterCalls == 2 && find.text('表示内容と印影を確認しました').evaluate().isNotEmpty, 'second preview raster requested and route visible');
      stdout.writeln('INVOICE_APP_STAGE=second_raster_pending');
      expect(previewButton().onPressed, isNull);
      emitPage!();
      await until(() => find.byType(Image).evaluate().isNotEmpty, 'raster page emitted');
      expect(previewButton().onPressed, isNull, reason: 'a page before raster completion cannot authorize consent');
      emitEnd!();
      await until(() => previewButton().onPressed != null, 'all raster pages decoded and displayed');
      stdout.writeln('INVOICE_APP_STAGE=raster_display_complete');
      await tester.tap(find.text('表示内容と印影を確認しました')); await tester.pumpAndSettle();
      await tester.tap(find.text('請求書の最終承認と注文請書の内容を確認しました')); await tester.pump();
      expect(approveButton().onPressed, isNull); expect(sent(), 0);
      await tester.tap(find.text('会社に登録した自社の角印の使用を承認します')); await tester.pump();
      expect(approveButton().onPressed, isNotNull);
      stdout.writeln('INVOICE_APP_STAGE=explicit_choices');
      await tester.tap(find.text('承認する')); await tester.pump();
      await until(() => controller.state == InvoiceNoticeRecoveryState.recorded, 'lost committed response then fresh receipt');
      stdout.writeln('INVOICE_APP_STAGE=recorded');
      await tester.pump(); expect(find.text('承認済み'), findsOneWidget); expect(sent(), 1); expect(legacyReads, 0);
      final command = trace.singleWhere((row) => (row['path'] as String).endsWith('/confirm'))['body'] as Map;
      expect(command['local_document_id'], isNot(invoice)); expect(command['revision'], isA<int>());
      expect(command['expected_hash'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(command['financial_confirmed'], true); expect(command['seal_confirmed'], true);
      expect(trace.where((row) => (row['path'] as String).endsWith('/result')), hasLength(1));
      await tester.runAsync(() => client.auth.signOut(scope: SignOutScope.local));
      await tester.runAsync(() => client.auth.signInWithPassword(email: env['SKO_INVOICE_APP_EMAIL']!, password: env['SKO_INVOICE_APP_PASSWORD']!));
      await tester.pump(); expect(controller.state, InvoiceNoticeRecoveryState.invalidated);
      expect(find.text('承認済み'), findsNothing); expect(sent(), 1);
      stdout.writeln('INVOICE_APP_STAGE=logout_terminal');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      messenger.setMockMethodCallHandler(channel, null); controller.dispose();
      await tester.runAsync(client.dispose);
    }
  // Outside dedicated CI this fixture is skipped. Required CI never skips a
  // missing certificate: the body fails instead.
  }, skip: Platform.environment['SKO_INVOICE_APP_CERT'] == null && Platform.environment['SKO_INVOICE_APP_REQUIRED'] != 'true');
}

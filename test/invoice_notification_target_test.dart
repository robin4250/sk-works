import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_list_card.dart';
import 'package:sk_works/features/invoices/invoice_cloud_page.dart';
import 'package:sk_works/features/invoices/invoice_notification_page.dart';

const _id = '11111111-1111-4111-8111-111111111111';
const _otherId = '22222222-2222-4222-8222-222222222222';
InvoiceCalculationResult _invoice({
  String id = _id,
  bool pending = false,
  String? readinessError,
}) => InvoiceCalculationResult(
  invoiceId: id,
  customerId: id == _id ? 'Saved customer' : 'Other customer',
  billingPeriod: '2025-08',
  detailMode: InvoiceDetailMode.consolidatedOnly,
  siteCalculations: const [],
  taxRateBps: 1000,
  grandTotalYenOverride: 12345,
  routeQuantityPending: pending,
  outputReadinessError: readinessError,
);

class _Source implements InvoiceNoticeSource {
  @override
  String? actor = 'actor-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  List<InvoiceCalculationResult> rows = [_invoice(), _invoice(id: _otherId)];
  Completer<List<InvoiceCalculationResult>>? gate;
  bool denied = false;
  int reads = 0;
  @override
  Stream<String?> get actorChanges => changes.stream;
  @override
  Future<List<InvoiceCalculationResult>> load() async {
    reads++;
    if (denied) throw StateError('private backend failure');
    return gate == null ? rows : gate!.future;
  }
}

Future<void> _show(
  WidgetTester tester,
  _Source source, {
  String id = _id,
  void Function(InvoiceCalculationResult)? preview,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: InvoiceNotificationPage(
        invoiceId: id,
        source: source,
        previewBuilder: (invoice) {
          preview?.call(invoice);
          return const Scaffold(body: Text('Saved invoice preview'));
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('notification preview disallows legacy initialization while normal entry keeps compatibility', () {
    final saved = _invoice();
    final noticePreview = invoiceNotificationPreview(saved, notificationId: '00000000-0000-0000-0000-000000000123');
    expect(noticePreview.invoice, same(saved));
    expect(noticePreview.allowLegacyApprovalInitialization, isFalse);
    expect(noticePreview.approvalFromNotification, isTrue);
    expect(noticePreview.approvalNotificationId, '00000000-0000-0000-0000-000000000123');
    expect(InvoicePreviewPage(invoice: saved).approvalFromNotification, isFalse);
    expect(invoiceNotificationPreview(saved).approvalFromNotification, isFalse);
    expect(invoiceNotificationPreview(saved, notificationId: 'bad-id').approvalFromNotification, isFalse);
    expect(InvoicePreviewPage(invoice: saved).allowLegacyApprovalInitialization, isTrue);
  });

  tearDown(
    () => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'),
  );
  setUp(() {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets(
    'exact UUID keeps older saved month/customer and excludes unrelated invoice',
    (tester) async {
      final source = _Source();
      await _show(tester, source);
      final card = tester.widget<InvoiceListCard>(find.byType(InvoiceListCard));
      expect(identical(card.invoice, source.rows.first), true);
      expect(find.text('Saved customer'), findsOneWidget);
      expect(find.text('2025-08'), findsOneWidget);
      expect(find.text('Other customer'), findsNothing);
      expect(find.text('Saved invoice preview'), findsNothing);
      expect(source.reads, 1);
    },
  );

  for (final id in [
    '',
    'bad',
    ' $_id ',
    '33333333-3333-4333-8333-333333333333',
  ]) {
    testWidgets('invalid or absent invoice $id never falls back', (
      tester,
    ) async {
      final source = _Source();
      await _show(tester, source, id: id);
      expect(find.byType(InvoiceListCard), findsNothing);
      expect(find.text('請求書を開く'), findsNothing);
      expect(find.text('対象の請求書は見つからないか、閲覧できません。'), findsOneWidget);
      if (id != '33333333-3333-4333-8333-333333333333') expect(source.reads, 0);
    });
  }

  testWidgets('missing actor shows unavailable without reading or spinning', (
    tester,
  ) async {
    final source = _Source()..actor = null;
    await _show(tester, source);
    expect(source.reads, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('対象の請求書は見つからないか、閲覧できません。'), findsOneWidget);
    expect(find.byType(InvoiceListCard), findsNothing);
  });

  testWidgets(
    'uninitialized default source shows unavailable without spinning',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: InvoiceNotificationPage(invoiceId: _id)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('対象の請求書は見つからないか、閲覧できません。'), findsOneWidget);
      expect(find.byType(InvoiceListCard), findsNothing);
    },
  );

  testWidgets('duplicate exact targets fail closed', (tester) async {
    final source = _Source()..rows = [_invoice(), _invoice()];
    await _show(tester, source);
    expect(find.byType(InvoiceListCard), findsNothing);
  });

  testWidgets('denied load exposes no backend error or fallback', (
    tester,
  ) async {
    final source = _Source()..denied = true;
    await _show(tester, source);
    expect(find.byType(InvoiceListCard), findsNothing);
    expect(find.textContaining('private backend failure'), findsNothing);
  });

  testWidgets('pending amount stays pending and cannot open a preview', (
    tester,
  ) async {
    final source = _Source()..rows = [_invoice(pending: true)];
    var previews = 0;
    await _show(tester, source, preview: (_) => previews++);
    expect(find.text('未確定'), findsOneWidget);
    expect(find.text('¥0'), findsNothing);
    expect(find.text('請求書を開く'), findsNothing);
    await tester.tap(find.byType(InvoiceListCard));
    await tester.pump();
    expect(previews, 0);
  });

  for (final readinessError in ['', 'private setting failure']) {
    testWidgets(
      'unready saved output blocks preview without exposing backend details: $readinessError',
      (tester) async {
        final source = _Source()
          ..rows = [_invoice(readinessError: readinessError)];
        var previews = 0;
        await _show(tester, source, preview: (_) => previews++);
        expect(find.text('請求書を開く'), findsNothing);
        expect(find.textContaining('private setting failure'), findsNothing);
        expect(find.text('帳票の出力準備を確認してください。'), findsOneWidget);
        await tester.tap(find.byType(InvoiceListCard));
        await tester.pump();
        expect(previews, 0);
      },
    );
  }

  testWidgets(
    'explicit open passes the original saved invoice into its disposable preview',
    (tester) async {
      final source = _Source();
      InvoiceCalculationResult? previewed;
      await _show(tester, source, preview: (value) => previewed = value);
      expect(previewed, isNull);
      await tester.tap(find.text('請求書を開く'));
      await tester.pump();
      expect(identical(previewed, source.rows.first), true);
      expect(find.text('Saved invoice preview'), findsOneWidget);
      expect(source.reads, 1);
    },
  );

  testWidgets(
    'actor ABA permanently removes the preview and refuses resume reload',
    (tester) async {
      final source = _Source();
      await _show(tester, source);
      await tester.tap(find.text('請求書を開く'));
      await tester.pump();
      source.actor = 'actor-b';
      source.changes.add(source.actor);
      source.actor = 'actor-a';
      source.changes.add(source.actor);
      await tester.pump();
      expect(find.text('Saved invoice preview'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(source.reads, 1);
      expect(find.byType(InvoiceListCard), findsNothing);
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'late read after actor ABA cannot restore target; error=$fails',
      (tester) async {
        final source = _Source()
          ..gate = Completer<List<InvoiceCalculationResult>>();
        await _show(tester, source);
        source.actor = 'actor-b';
        source.changes.add(source.actor);
        source.actor = 'actor-a';
        source.changes.add(source.actor);
        if (fails) {
          source.gate!.completeError(StateError('late failure'));
        } else {
          source.gate!.complete(source.rows);
        }
        await tester.pumpAndSettle();
        expect(find.byType(InvoiceListCard), findsNothing);
        expect(find.textContaining('late failure'), findsNothing);
      },
    );
  }

  testWidgets(
    'background disposes preview; same actor resume rereads before another explicit open',
    (tester) async {
      final source = _Source();
      await _show(tester, source);
      await tester.tap(find.text('請求書を開く'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(find.text('Saved invoice preview'), findsNothing);
      expect(find.byType(InvoiceListCard), findsNothing);
      source.gate = Completer<List<InvoiceCalculationResult>>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(source.reads, 2);
      expect(find.text('Saved invoice preview'), findsNothing);
      source.gate!.complete(source.rows);
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceListCard), findsOneWidget);
      expect(find.text('Saved invoice preview'), findsNothing);
    },
  );

  testWidgets('initial background performs no read until same actor resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final source = _Source();
    await _show(tester, source);
    expect(source.reads, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(source.reads, 1);
    expect(find.byType(InvoiceListCard), findsOneWidget);
  });

  testWidgets(
    'open target reacts to language change without replacing state or reloading',
    (tester) async {
      final source = _Source();
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: SkoLanguageController.pack,
          child: InvoiceNotificationPage(invoiceId: _id, source: source),
          builder: (context, pack, child) => MaterialApp(
            locale: Locale(pack.languageCode),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('ja'), Locale('en')],
            home: child,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(InvoiceNotificationPage));
      expect(find.text('請求書を開く'), findsOneWidget);
      SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
      await tester.pumpAndSettle();
      expect(find.text('Open invoice'), findsOneWidget);
      expect(find.text('請求書を開く'), findsNothing);
      expect(find.text('Saved customer'), findsOneWidget);
      expect(find.text('2025-08'), findsOneWidget);
      expect(
        identical(state, tester.state(find.byType(InvoiceNotificationPage))),
        true,
      );
      expect(source.reads, 1);
    },
  );

  testWidgets('late response after dispose produces no target or exception', (
    tester,
  ) async {
    final source = _Source()
      ..gate = Completer<List<InvoiceCalculationResult>>();
    await _show(tester, source);
    await tester.pumpWidget(const SizedBox());
    source.gate!.complete(source.rows);
    await tester.pumpAndSettle();
    expect(find.byType(InvoiceListCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

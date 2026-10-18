import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/invoices/invoice_approval_repository.dart';
import 'package:sk_works/features/invoices/invoice_stamp_surname_dialog.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_cloud_page.dart';
import 'package:sk_works/features/invoices/invoice_notification_page.dart';
import 'package:sk_works/features/notifications/notification_preview_route_scope.dart';

const _id = '11111111-1111-4111-8111-111111111111';

class _Source implements InvoiceNoticeSource {
  @override
  String? actor = 'actor-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get actorChanges => changes.stream;
  @override
  Future<List<InvoiceCalculationResult>> load() async => [
    const InvoiceCalculationResult(
      invoiceId: _id,
      customerId: 'Saved customer',
      billingPeriod: '2025-08',
      detailMode: InvoiceDetailMode.consolidatedOnly,
      siteCalculations: [],
      taxRateBps: 1000,
      grandTotalYenOverride: 1000,
    ),
  ];
}

class _Result {
  bool? result;
  bool completed = false;
  int writes = 0;
  String? rawResult;
  bool rawCompleted = false;
  InvoiceApprovalRepository? surnameRepository;
}

class _Preview extends StatelessWidget {
  const _Preview(this.result);
  final _Result result;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scoped preview')),
    body: Column(
      children: [
        Text(
          NotificationPreviewRouteScope.isScoped(context)
              ? 'Scoped'
              : 'Unscoped',
        ),
        FilledButton(
          onPressed: () async {
            result.result = await showInvoiceApprovalCancellationConfirmation(
              context,
            );
            result.completed = true;
            if (result.result == true) result.writes++;
          },
          child: const Text('Cancellation dialog'),
        ),
        FilledButton(
          onPressed: () async {
            result.rawResult = await showDialog<String>(
              context: context,
              useRootNavigator: !NotificationPreviewRouteScope.isScoped(
                context,
              ),
              builder: (_) =>
                  const AlertDialog(title: Text('Raw nullable dialog')),
            );
            result.rawCompleted = true;
          },
          child: const Text('Raw dialog'),
        ),
        if (result.surnameRepository != null)
          FilledButton(
            onPressed: () async {
              result.result = await editInvoiceStampSurname(
                context,
                result.surnameRepository!,
                _id,
              );
              result.completed = true;
              if (result.result == true) result.writes++;
            },
            child: const Text('Surname dialog'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: const Text('Nested child'))),
            ),
          ),
          child: const Text('Child route'),
        ),
      ],
    ),
  );
}

Future<void> _show(
  WidgetTester tester,
  _Source source,
  _Result result, {
  GlobalKey<NavigatorState>? root,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: root,
      home: InvoiceNotificationPage(
        invoiceId: _id,
        source: source,
        previewBuilder: (_) => _Preview(result),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('請求書を開く'));
  await tester.pumpAndSettle();
  expect(find.text('Scoped'), findsOneWidget);
}

Future<void> _background(WidgetTester tester) async {
  // Inactive still permits a frame: verify immediate preview disposal before
  // hidden/paused suspend frame scheduling, using the platform lifecycle order.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pumpAndSettle();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
}

void _resumeBinding(WidgetsBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState != AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

Future<void> _resume(WidgetTester tester) async {
  _resumeBinding(tester.binding);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _resumeBinding(TestWidgetsFlutterBinding.ensureInitialized()));

  testWidgets('scope is absent for ordinary application routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              Text(NotificationPreviewRouteScope.isScoped(context).toString()),
        ),
      ),
    );
    expect(find.text('false'), findsOneWidget);
  });

  testWidgets(
    'base local history registers after installation and closes once',
    (tester) async {
      final root = GlobalKey<NavigatorState>();
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          home: NotificationPreviewHost(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Installed preview')),
            ),
            onClose: () => closes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(root.currentState!.canPop(), false);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(closes, 1);
      expect(root.currentState!.canPop(), false);
      expect(find.text('Installed preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview AppBar back returns to its invoice summary', (
    tester,
  ) async {
    await _show(tester, _Source(), _Result());
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Scoped preview'), findsNothing);
    expect(find.text('Saved customer'), findsOneWidget);
    expect(find.text('請求書を開く'), findsOneWidget);
  });

  testWidgets('OS back pops a child route before closing the preview', (
    tester,
  ) async {
    await _show(tester, _Source(), _Result());
    await tester.tap(find.text('Child route'));
    await tester.pumpAndSettle();
    expect(find.text('Nested child'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Nested child'), findsNothing);
    expect(find.text('Scoped preview'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Saved customer'), findsOneWidget);
    expect(find.text('Scoped preview'), findsNothing);
  });

  for (final reason in ['actor ABA', 'background', 'stream error', 'dispose']) {
    testWidgets(
      'real cancellation dialog is removed on $reason without a write',
      (tester) async {
        final source = _Source();
        final result = _Result();
        await _show(tester, source, result);
        await tester.tap(find.text('Cancellation dialog'));
        await tester.pumpAndSettle();
        expect(find.text('承認を解除しますか？'), findsOneWidget);
        switch (reason) {
          case 'actor ABA':
            source.actor = 'actor-b';
            source.changes.add(source.actor);
            source.actor = 'actor-a';
            source.changes.add(source.actor);
          case 'background':
            await _background(tester);
          case 'stream error':
            source.changes.addError(StateError('fixture actor stream error'));
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
        }
        await tester.pumpAndSettle();
        expect(find.text('承認を解除しますか？'), findsNothing);
        expect(find.text('承認を解除'), findsNothing);
        expect(result.writes, 0);
        expect(result.completed, true);
        expect(
          result.result,
          false,
        ); // Real helper normalizes dismissed null to false.
        if (reason != 'dispose') {
          await _resume(tester);
          await tester.pumpAndSettle();
          expect(find.text('承認を解除しますか？'), findsNothing);
          expect(result.writes, 0);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'raw nullable dialog completes with null when scope is discarded',
    (tester) async {
      final source = _Source();
      final result = _Result();
      await _show(tester, source, result);
      await tester.tap(find.text('Raw dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Raw nullable dialog'), findsOneWidget);
      await _background(tester);
      await tester.pumpAndSettle();
      expect(find.text('Raw nullable dialog'), findsNothing);
      expect(result.rawCompleted, true);
      expect(result.rawResult, isNull);
      expect(result.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared surname dialog discards input and completes false without an HTTP write',
    (tester) async {
      var requests = 0;
      final transport = MockClient((request) async {
        requests++;
        expect(request.url.host, 'fixture.invalid');
        return http.Response('{}', 500);
      });
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://fixture.invalid',
          'public_fixture',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ))!;
      // SDK disposal awaits its isolate; use real async as existing chat fixtures do.
      addTearDown(() => tester.runAsync(client.dispose));
      final source = _Source();
      final result = _Result()
        ..surnameRepository = InvoiceApprovalRepository.forTesting(client);
      await _show(tester, source, result);
      await tester.tap(find.text('Surname dialog'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保存しない名字');
      expect(find.text('保存しない名字'), findsOneWidget);
      await _background(tester);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('保存しない名字'), findsNothing);
      expect(result.completed, true);
      expect(result.result, false);
      expect(requests, 0);
      expect(result.writes, 0);
      await _resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('保存しない名字'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scope disposal leaves an unrelated root dialog untouched', (
    tester,
  ) async {
    final source = _Source();
    final root = GlobalKey<NavigatorState>();
    await _show(tester, source, _Result(), root: root);
    unawaited(
      showDialog<void>(
        context: root.currentContext!,
        useRootNavigator: true,
        builder: (context) =>
            const AlertDialog(title: Text('Unrelated root dialog')),
      ),
    );
    await tester.pumpAndSettle();
    source.actor = 'actor-b';
    source.changes.add(source.actor);
    await tester.pumpAndSettle();
    expect(find.text('Unrelated root dialog'), findsOneWidget);
    expect(root.currentState!.canPop(), true);
    root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Scoped preview'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

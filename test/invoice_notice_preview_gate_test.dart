import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/invoices/invoice_notice_approval_panel.dart';
import 'package:sk_works/features/invoices/invoice_notice_recovery_controller.dart';

void main() {
  testWidgets('invalidation while renderer capability is pending never dispatches retained PDF bytes', (tester) async {
    const id = '10000000-0000-0000-0000-000000000001', revision = '2026-10-29T00:00:00Z';
    const channel = MethodChannel('net.nfet.printing');
    final capabilities = Completer<Map<String, dynamic>>();
    var info = 0, rasters = 0, sent = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'printingInfo') { info++; return capabilities.future; }
      if (call.method == 'rasterPdf') { rasters++; }
      return null;
    });
    final recovery = InvoiceNoticeRecoveryController(actor: () => 'actor', session: () => 'session', explicitConsentRequired: true,
      openTicket: (_) async => {'notification_id': id, 'invoice_id': id, 'ticket_id': id,
        'source_revision': revision, 'status': 'ready', 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String()},
      operationForTicket: (_) => InvoiceNoticeOperation(ticketId: id, localDocumentId: id, companyId: id,
        revision: 1, requestId: id, expectedHash: List.filled(64, 'a').join(), expectedPreview: {'value': 1}),
      confirm: (_) async { sent++; return true; },
      confirmWithConsent: (_, {required financialConfirmed, required sealConfirmed}) async { sent++; return true; },
      readResult: (_) async => null,
      buildOwnPreview: () async => Uint8List.fromList([37, 80, 68, 70]));
    try {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InvoiceNoticeApprovalPanel(controller: null,
        recoveryController: recovery, notificationId: id, invoiceId: id, revision: revision,
        isApprover: true, confirmSavedApproval: () async => false))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('注文請書と登録印影を確認'));
      for (var frame = 0; frame < 5 && info == 0; frame++) { await tester.pump(); }
      expect(info, 1); expect(rasters, 0);
      // The incoming route is in its initial offstage measurement while the
      // capability future is deliberately held; inspect its built control.
      final acknowledgement = tester.widget<FilledButton>(find.ancestor(of: find.text('表示内容と印影を確認しました', skipOffstage: false),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton, skipOffstage: false)).first);
      expect(acknowledgement.onPressed, isNull);
      recovery.invalidate();
      capabilities.complete({'canRaster': true});
      await tester.pumpAndSettle();
      expect(rasters, 0); expect(sent, 0);
      expect(find.text('表示内容と印影を確認しました'), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally { recovery.dispose(); tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null); }
  });
  for (final completes in [true, false]) {
  testWidgets(completes ? 'completed raster waits for reading every page without timing out the reader' : 'unfinished raster still expires at the technical deadline', (tester) async {
    const id = '10000000-0000-0000-0000-000000000001', revision = '2026-10-29T00:00:00Z';
    const channel = MethodChannel('net.nfet.printing');
    const codec = StandardMethodCodec();
    final messenger = tester.binding.defaultBinaryMessenger;
    Future<void> Function()? finish;
    var sent = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'printingInfo') { return {'canRaster': true}; }
      if (call.method == 'rasterPdf') {
        final job = (call.arguments as Map)['job'];
        finish = () async {
          final rgba = Uint8List(100 * 1000 * 4);
          for (var i = 3; i < rgba.length; i += 4) { rgba[i] = 255; }
          for (var page = 0; page < 3; page++) {
            messenger.handlePlatformMessage(channel.name, codec.encodeMethodCall(MethodCall('onPageRasterized',
              {'job': job, 'width': 100, 'height': 1000, 'image': rgba})), (_) {});
          }
          if (completes) { messenger.handlePlatformMessage(channel.name, codec.encodeMethodCall(MethodCall('onPageRasterEnd', {'job': job})), (_) {}); }
        };
      }
      return null;
    });
    final recovery = InvoiceNoticeRecoveryController(actor: () => 'actor', session: () => 'session', explicitConsentRequired: true,
      openTicket: (_) async => {'notification_id': id, 'invoice_id': id, 'ticket_id': id,
        'source_revision': revision, 'status': 'ready', 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String()},
      operationForTicket: (_) => InvoiceNoticeOperation(ticketId: id, localDocumentId: id, companyId: id,
        revision: 1, requestId: id, expectedHash: List.filled(64, 'a').join(), expectedPreview: {'value': 1}),
      confirm: (_) async { sent++; return true; }, readResult: (_) async => null,
      buildOwnPreview: () async => Uint8List.fromList([37, 80, 68, 70]));
    FilledButton acknowledgement() => tester.widget<FilledButton>(find.ancestor(of: find.text('表示内容と印影を確認しました'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton)).first);
    Future<void> ioFrames([int count = 20]) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    try {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InvoiceNoticeApprovalPanel(controller: null,
        recoveryController: recovery, notificationId: id, invoiceId: id, revision: revision,
        isApprover: true, confirmSavedApproval: () async => false))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('注文請書と登録印影を確認'));
      await ioFrames(); expect(finish, isNotNull);
      await finish!(); await ioFrames();
      expect(find.byType(Image).evaluate().length, lessThan(3), reason: 'offscreen pages stay lazy');
      expect(acknowledgement().onPressed, isNull, reason: 'unvisited pages cannot authorize consent');
      await tester.pump(const Duration(seconds: 25));
      if (!completes) {
        expect(find.text('本文と印影を表示できません'), findsOneWidget);
        expect(acknowledgement().onPressed, isNull); expect(sent, 0);
        await tester.pumpWidget(const SizedBox.shrink()); return;
      }
      expect(find.text('本文と印影を表示できません'), findsNothing, reason: 'human reading time is not raster loading time');
      expect(acknowledgement().onPressed, isNull);
      // Image.memory scales a tall page to the viewport width. Traverse
      // each viewport rather than assuming a fixed total document height.
      for (var viewport = 0; viewport < 30 && acknowledgement().onPressed == null; viewport++) {
        await tester.drag(find.byType(ListView), const Offset(0, -500)); await ioFrames(5);
      }
      expect(acknowledgement().onPressed, isNotNull, reason: 'all rendered pages were decoded and visited');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await ioFrames();
      expect(recovery.state, InvoiceNoticeRecoveryState.invalidated);
      expect(find.text('表示内容と印影を確認しました'), findsNothing);
      expect(sent, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await ioFrames(); expect(find.text('表示内容と印影を確認しました'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      recovery.dispose(); messenger.setMockMethodCallHandler(channel, null);
      await tester.binding.setSurfaceSize(null);
    }
  });
  }

}

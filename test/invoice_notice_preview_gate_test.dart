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
      final acknowledgement = tester.widget<FilledButton>(find.ancestor(of: find.text('表示内容と印影を確認しました'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton)).first);
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
}

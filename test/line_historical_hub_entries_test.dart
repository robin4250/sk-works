import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';
import 'package:sk_works/features/chat/line_import_repository.dart';

void main() {
  for (final master in [true, false]) {
    testWidgets('ordinary hub hides invoice and rates for master=$master', (tester) async {
      await tester.pumpWidget(MaterialApp(home: LineTalkHubPage(
        accessLoader: () async => LineTalkHubAccess(isMaster: master,
          canViewInvoice: true, settingsUnavailable: true,
          features: const LineImportFeatures(invoice: true)))));
      await tester.pumpAndSettle();
      expect(find.text('請求書'), findsNothing);
      expect(find.text('単価設定'), findsNothing);
      expect(find.text('トーク'), findsOneWidget);
      expect(find.text('マスター権限'), master ? findsOneWidget : findsNothing);
    });
  }
}

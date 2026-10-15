import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/payroll/site_contract_notification_page.dart';

void main() {
  test('contract notification resolves its receipt ID instead of trusting action ID', () {
    final target = notificationDestination(AppNotificationRecord(
      id: 'exact-receipt-notice', kind: 'site_payment_agreement', title: '契約',
      body: '', createdAt: DateTime(2026), read: false,
      actionKey: 'site_payment_agreement', actionId: 'untrusted-item',
    ));
    expect(target, isA<SiteContractNotificationPage>());
    expect((target as SiteContractNotificationPage).notificationId, 'exact-receipt-notice');
    expect(notificationModule('site_payment_agreement'), 'sites');
  });

  testWidgets('contract notice cannot open a contract without login', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SiteContractNotificationPage(notificationId: 'notice'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ログインが必要です。'), findsOneWidget);
    expect(find.text('押印して送信'), findsNothing);
  });
}

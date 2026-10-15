import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/notification_explanation_page.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/companies/company_profile_review_page.dart';

const item = AttentionCenterItem(
  id: 'notice',
  source: 'notification',
  title: '現場の確認',
  body: '対象現場の内容をご確認ください。',
  state: AttentionCenterState.pending,
  actionKey: 'site_share_approval',
  actionId: 'saved-target',
);

void main() {
  test(
    'company link notice fails closed without an authenticated backend',
    () async {
      expect(await companyLinkNotificationAvailable(), isFalse);
      expect(companyLinkNotificationDestination('request-id'), isNull);
      expect(companyLinkNotificationDestination(null), isNull);
    },
  );

  testWidgets(
    'company link notice keeps its explanation when workspace is OFF',
    (tester) async {
      const request = AttentionCenterItem(
        id: 'company-notice',
        source: 'notification',
        title: '会社連携申請',
        body: '開始月を確認してください',
        state: AttentionCenterState.pending,
        actionKey: 'company_link_request',
        actionId: 'request-id',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationExplanationPage(
            item: request,
            canOpenTarget: () async => false,
            openTarget: (_) async => fail('OFF company linking must not open'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('会社連携申請'), findsOneWidget);
      expect(find.textContaining('承認前に会社連携は成立しません'), findsOneWidget);
      expect(find.text('開く'), findsNothing);
    },
  );


  test('profile notification preserves the exact target and fails closed without login', () async {
    final target = notificationDestination(AppNotificationRecord(
      id: 'profile-notice', kind: 'company_profile_review', title: '更新', body: '',
      createdAt: DateTime(2026), read: false,
      actionKey: 'company_profile_review', actionId: 'specific-review-id',
    ));
    expect(target, isA<CompanyProfileReviewPage>());
    expect((target as CompanyProfileReviewPage).initialReviewId, 'specific-review-id');
    expect(await companyProfileNotificationAvailable(), isFalse);
  });
  testWidgets('profile OFF retains explanation without opening an update', (tester) async {
    const request = AttentionCenterItem(
      id: 'profile-notice', source: 'notification', title: '会社情報の更新',
      body: '更新候補を確認', state: AttentionCenterState.pending,
      actionKey: 'company_profile_review', actionId: 'specific-review-id',
    );
    await tester.pumpWidget(MaterialApp(home: NotificationExplanationPage(
      item: request, canOpenTarget: () async => false,
      openTarget: (_) async => fail('disabled review must not open'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('会社情報の更新'), findsOneWidget);
    expect(find.textContaining('旧情報・契約単価・過去帳票は保持'), findsOneWidget);
    expect(find.text('開く'), findsNothing);
  });

  testWidgets(
    'explanation never acts until link, and back returns to explanation',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationExplanationPage(
            item: item,
            openTarget: (context) async {
              opened++;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('対象現場')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(find.text('このページは右上のベルマークから何度も見れます！'), findsOneWidget);
      await tester.ensureVisible(find.text('開く'));
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('対象現場'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('通知の説明'), findsOneWidget);
      expect(find.text('開く'), findsOneWidget);
    },
  );

  testWidgets('disabled feature retains explanation and hides open button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationExplanationPage(
          item: item,
          canOpenTarget: () async => false,
          openTarget: (_) async => fail('disabled target opened'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('現場の確認'), findsOneWidget);
    expect(find.text('開く'), findsNothing);
  });
}

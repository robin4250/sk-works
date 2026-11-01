import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';
import 'package:sk_works/features/notifications/attention_center_repository.dart';
import 'package:sk_works/features/notifications/notification_explanation_page.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';
import 'package:sk_works/features/sites/site_order_site_actions.dart';
import 'package:sk_works/features/sites/site_order_workflow_page.dart';

import 'site_order_notification_scoped_read_test.dart' as fixture;

AppNotificationRecord _record({String packageId = fixture.noticePackage}) => AppNotificationRecord(
  id: fixture.noticeId, kind: 'approval', title: '注文の通知', body: '開く前の非公開工事',
  createdAt: DateTime(2026, 10, 31), read: false,
  actionKey: 'site_order_package', actionId: packageId);
class _Attention implements AttentionCenterRepository {
  _Attention() {
    final record = _record();
    final item = AttentionCenterItem(id: fixture.noticeId, source: 'notifications',
      title: record.title, body: record.body, state: AttentionCenterState.pending,
      actionKey: record.actionKey, actionId: record.actionId, targetName: '一覧の非公開工事名');
    data = AttentionCenterData(snapshot: AttentionCenterSnapshot([item], now: DateTime(2026, 10, 31)),
      notificationsById: {record.id: record},
      notificationIdsByItemKey: {item.deduplicationKey: [record.id]}, unavailableSources: {});
  }
  late AttentionCenterData data;
  @override Future<AttentionCenterData> load({Set<String>? availableActionKeys,
      String? companyId, String? Function()? currentCompany}) async => data;
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 250 && !ready(); index++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Expected route stage did not complete');
}
Future<void> _cleanup(WidgetTester tester, fixture.NoticeFixture f) async {
  await tester.pumpWidget(const SizedBox.shrink()); await tester.pump();
  await tester.runAsync(f.close);
}
Future<({fixture.NoticeFixture fixture, _Attention attention})> _mount(
    WidgetTester tester, {String mode = 'normal', String? Function()? currentCompany}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // SDK construction, initialization and teardown use the real zone. HTTP and
  // identities remain synthetic; no GoTrue, RLS or hosted-delivery proof.
  final f = (await tester.runAsync(fixture.NoticeFixture.create))!;
  f.wire.mode = mode;
  final attention = _Attention();
  await tester.pumpWidget(MaterialApp(home: NotificationsPage(
    companyId: fixture.noticeCompany, currentCompany: currentCompany,
    attentionRepository: attention, notificationRepository: f.notifications,
    notificationClient: f.client, siteOrderApiFactory: () => f.api)));
  await tester.pumpAndSettle();
  addTearDown(() => _cleanup(tester, f));
  return (fixture: f, attention: attention);
}
Future<void> _explanation(WidgetTester tester) async {
  await tester.tap(find.text('注文・請書のお知らせ'));
  await _wait(tester, () => find.byType(NotificationExplanationPage).evaluate().isNotEmpty &&
    find.text('開く').evaluate().isNotEmpty);
}
Future<void> _openTarget(WidgetTester tester) async {
  await tester.ensureVisible(find.text('開く'));
  await tester.tap(find.text('開く'));
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('real notification entry authorizes a saved package without a local site or generation call', (tester) async {
    final f = (await _mount(tester)).fixture;
    expect(find.text('開く前の非公開工事'), findsNothing);
    expect(find.text('一覧の非公開工事名'), findsNothing);
    await _explanation(tester);
    expect(f.wire.patches, 0); // Reading the explanation is not target admission.
    await _openTarget(tester);
    await _wait(tester, () => find.byType(SiteOrderWorkflowPage).evaluate().isNotEmpty &&
      find.text('権限確認後の工事').evaluate().isNotEmpty);
    final host = tester.widget<SiteOrderSiteActionsPage>(find.byType(SiteOrderSiteActionsPage));
    expect(host.packageId, fixture.noticePackage); expect(host.siteId, '');
    expect(f.wire.patches, 1); expect(f.wire.unsafePatches, 0);
    expect(f.wire.businessWrites, 0);
    expect(find.text('内容と自社印を確認して承認'), findsNothing);
    expect(find.text('注文を辞退'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final mode in ['denied', 'wrong-package', 'unavailable', 'row-package']) {
    testWidgets('$mode keeps a generic state and the unread notification', (tester) async {
      final mounted = await _mount(tester, mode: mode), f = mounted.fixture;
      await tester.tap(find.text('注文・請書のお知らせ'));
      await _wait(tester, () => find.text('通知の注文書').evaluate().isNotEmpty);
      expect(find.byType(NotificationExplanationPage), findsNothing);
      expect(find.text('開く前の非公開工事'), findsNothing);
      expect(find.text('権限確認後の工事'), findsNothing);
      expect(f.wire.patches, 0); expect(f.wire.businessWrites, 0);
      expect(mounted.attention.data.notificationsById[fixture.noticeId]!.read, isFalse);
      await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
      expect(find.text('注文・請書のお知らせ'), findsOneWidget);
    });
  }
  testWidgets('same-actor new SID during preflight never exposes the private body or starts read marking', (tester) async {
    final f = (await _mount(tester)).fixture;
    f.wire.holdDetail = true; f.wire.detailHold = Completer<void>(); f.wire.detailStarted = Completer<void>();
    await tester.tap(find.text('注文・請書のお知らせ'));
    await _wait(tester, () => f.wire.detailStarted!.isCompleted);
    await tester.runAsync(f.changeSession); f.wire.detailHold!.complete();
    await _wait(tester, () => find.text('通知の注文書').evaluate().isNotEmpty);
    expect(find.text('開く前の非公開工事'), findsNothing);
    expect(f.wire.patches, 0); expect(f.wire.businessWrites, 0);
  });
  testWidgets('getter-only company change retires the explanation on its next scope check', (tester) async {
    var company = fixture.noticeCompany;
    final f = (await _mount(tester, currentCompany: () => company)).fixture;
    await _explanation(tester); company = fixture.otherNoticeId;
    await _openTarget(tester); await tester.pumpAndSettle();
    expect(find.text('開く前の非公開工事'), findsNothing);
    expect(f.wire.patches, 0); expect(f.wire.businessWrites, 0);
  });
  testWidgets('changing a notification target while click authorization waits never marks the old tuple', (tester) async {
    final mounted = await _mount(tester), f = mounted.fixture;
    await _explanation(tester);
    f.wire.holdDetail = true; f.wire.detailHold = Completer<void>(); f.wire.detailStarted = Completer<void>();
    await _openTarget(tester);
    await _wait(tester, () => f.wire.detailStarted!.isCompleted);
    mounted.attention.data.notificationsById[fixture.noticeId] = _record(packageId: fixture.otherNoticeId);
    f.wire.detailHold!.complete();
    await tester.pumpAndSettle();
    await _wait(tester, () => find.text('通知の注文書').evaluate().isNotEmpty ||
      find.text('通知一覧を開き直してください。').evaluate().isNotEmpty);
    expect(f.wire.patches, 0); expect(f.wire.businessWrites, 0);
    expect(find.text('権限確認後の工事'), findsNothing);
  });
  testWidgets('package identity replacement permanently retires the owned read-only route', (tester) async {
    final f = (await tester.runAsync(fixture.NoticeFixture.create))!;
    addTearDown(() => _cleanup(tester, f));
    await tester.pumpWidget(MaterialApp(home: notificationDestination(_record(), siteOrderApi: f.api)!));
    await _wait(tester, () => find.text('権限確認後の工事').evaluate().isNotEmpty);
    await tester.pumpWidget(MaterialApp(home: notificationDestination(
      _record(packageId: fixture.otherNoticeId), siteOrderApi: f.api)!));
    await tester.pumpAndSettle();
    expect(find.text('権限確認後の工事'), findsNothing);
    expect(f.api.uiRetired, isTrue); expect(f.wire.patches, 0); expect(f.wire.businessWrites, 0);
  });
  test('malformed package notification cannot construct a destination', () {
    expect(notificationDestination(_record(packageId: 'not-a-package')), isNull);
  });
}

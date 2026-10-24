import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/checkout_report_resume_repository.dart';
import 'package:sk_works/features/notifications/checkout_report_notification_repository.dart';
import 'package:sk_works/features/notifications/checkout_report_notification_page.dart';

import 'fixtures/checkout_report_notification_fixture.dart';

class Source implements CheckoutReportNotificationSource {
  final events = StreamController<String?>.broadcast();
  String? key = 'actor/session-a';
  bool resolved = false, unavailable = false;
  String state = 'reporter_signature_missing';
  Future<CheckoutReportNotificationSnapshot>? next;
  @override String? get sessionKey => key;
  @override Stream<String?> get sessionChanges => events.stream;
  @override Future<CheckoutReportNotificationSnapshot> load(String reportId) async {
    final pending = next; next = null;
    if (pending != null) { return await pending; }
    if (unavailable) { throw StateError('PRIVATE_REPLY'); }
    return CheckoutReportNotificationSnapshot.parse(registrationNotification(state: state, resolved: resolved),
      actorId: notificationActor, reportId: reportId);
  }
}
CheckoutReportResumeTarget target({String company = notificationCompany, String report = notificationReport, bool grouped = false}) =>
  CheckoutReportResumeTarget(companyId:company,workerId:notificationWorker,
    workDate:DateTime(2026,10,25), sourceClockInIds:grouped ? const ['10000000-0000-0000-0000-000000000008',notificationClockIn] : const [notificationClockIn],
    clockOutIds:grouped ? const ['10000000-0000-0000-0000-000000000009',notificationClockOut] : const [notificationClockOut],
    sourceClockInId:grouped ? '10000000-0000-0000-0000-000000000008' : notificationClockIn,
    clockOutId:grouped ? '10000000-0000-0000-0000-000000000009' : notificationClockOut,state:CheckoutReportState.partialSignature,
    siteId:notificationSite,reportId:report);
class Resume extends CheckoutReportResumeRepository {
  Resume(super.client);
  bool foreignCompany = false, changedReport = false, grouped = false;
  int validations = 0;
  @override Future<List<CheckoutReportResumeTarget>> loadDay({required String workerId, required DateTime workDate}) async =>
    [target(company: foreignCompany ? notificationSite : notificationCompany,grouped:grouped)];
  @override Future<CheckoutReportResumeTarget> revalidate(CheckoutReportResumeTarget value) async {
    validations++; return target(report: changedReport ? notificationSite : notificationReport,grouped:grouped);
  }
}
void main() {
  late Source source;
  late SupabaseClient client;
  late Resume resume;
  int opened = 0;
  setUp(() {
    source = Source();opened = 0;
    client = SupabaseClient('https://notification-page.invalid','synthetic-public',
      authOptions:const AuthClientOptions(autoRefreshToken:false));
    resume = Resume(client);
  });
  tearDown(() async { await source.events.close(); await client.dispose(); });
  Future<void> show(WidgetTester t) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.binding.setSurfaceSize(const Size(800,1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    addTearDown(() => t.pumpWidget(const SizedBox.shrink()));
    await t.pumpWidget(MaterialApp(home: CheckoutReportNotificationPage(reportId:notificationReport,
      source:source,resumeRepository:resume,opener:(context,value) async {
        opened++; expect(value.reportId,notificationReport);expect(value.companyId,notificationCompany);
        expect(value.sourceClockInId,notificationClockIn);expect(value.clockOutId,notificationClockOut);
        source.resolved = true;
      })));
    await t.pumpAndSettle();
  }
  testWidgets('dedicated notification resumes exact saved report with stage1 revalidation', (t) async {
    await show(t);expect(find.text('日報の報告者サインが未登録です。'),findsOneWidget);
    await t.tap(find.text('対象の日報を再開'));await t.pumpAndSettle();
    expect(opened,1);expect(resume.validations,2);
    expect(find.textContaining('登録に関する未完項目はありません'),findsOneWidget);
    expect(find.textContaining('給与への反映完了を示すものではありません'),findsOneWidget);
    expect(find.byType(LinearProgressIndicator),findsNothing);
  });
  testWidgets('multi-visit report keeps exact notified pair rather than first grouped visit', (t) async {
    resume.grouped = true;await show(t);
    await t.tap(find.text('対象の日報を再開'));await t.pumpAndSettle();
    expect(opened,1);expect(resume.validations,2);
  });
  testWidgets('responsible signature waiting remains a different resumable reason', (t) async {
    source.state = 'reporter_saved_waiting_supervisor';await show(t);
    expect(find.textContaining('現場責任者のサイン待ちです。'),findsOneWidget);
    expect(find.text('日報の報告者サインが未登録です。'),findsNothing);
    await t.tap(find.text('対象の日報を再開'));await t.pumpAndSettle();expect(opened,1);
  });
  for(final state in ['source_conflict','report_missing','signed_projection_unverified']) {
    testWidgets('$state never starts an editor or fabricates report completion', (t) async {
      source.state = state;await show(t);
      expect(find.text(checkoutReportNotificationLabel(state)),findsOneWidget);
      expect(find.text('対象の日報を再開'),findsNothing);
      expect(find.textContaining('登録に関する未完項目はありません'),findsNothing);
      expect(opened,0);
    });
  }
  testWidgets('other company or changed report cannot receive the normal report route', (t) async {
    resume.foreignCompany = true;await show(t);
    await t.tap(find.text('対象の日報を再開'));await t.pumpAndSettle();expect(opened,0);
    resume.foreignCompany = false;resume.changedReport = true;
    await t.tap(find.text('対象の日報を再開'));await t.pumpAndSettle();expect(opened,0);
    expect(find.textContaining('日報の状態が変わったか、対象を確認できません。'),findsOneWidget);
  });
  testWidgets('resolved stays read-only and help distinguishes read state from resolution', (t) async {
    source.resolved = true;await show(t);
    expect(find.text('対象の日報を再開'),findsNothing);expect(opened,0);
    await t.tap(find.byTooltip('使い方'));await t.pumpAndSettle();
    expect(find.textContaining('通知を既読にしても日報の未登録は解消しません。'),findsOneWidget);
  });
  testWidgets('unavailable reader never displays private error or resolved claim', (t) async {
    source.unavailable = true;await show(t);
    expect(find.textContaining('対象・権限・接続を確認してください。'),findsOneWidget);
    expect(find.textContaining('PRIVATE_REPLY'),findsNothing);
    expect(find.textContaining('登録に関する未完項目はありません'),findsNothing);
    expect(opened,0);
  });
  testWidgets('async same-actor SID ABA removes notification target permanently', (t) async {
    await show(t);
    source.key = 'actor/session-b';source.events.add(source.key);
    source.key = 'actor/session-a';source.events.add(source.key);
    await t.pumpAndSettle();
    expect(find.text('対象の日報を再開'),findsNothing);
    expect(find.textContaining('ログイン状態が変わりました。'),findsOneWidget);
    expect(opened,0);
  });
}

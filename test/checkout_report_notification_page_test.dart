import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
  Map<String, dynamic>? envelope;
  Future<CheckoutReportNotificationSnapshot>? next;
  @override String? get sessionKey => key;
  @override Stream<String?> get sessionChanges => events.stream;
  @override Future<CheckoutReportNotificationSnapshot> load(String reportId) async {
    final pending = next; next = null;
    if (pending != null) { return await pending; }
    if (unavailable) { throw StateError('PRIVATE_REPLY'); }
    return CheckoutReportNotificationSnapshot.parse(envelope ?? registrationNotification(state: state, resolved: resolved),
      actorId: notificationActor, reportId: reportId);
  }
}
CheckoutReportResumeTarget target({String company = notificationCompany, String report = notificationReport, bool grouped = false, bool bothSigned = false, CheckoutReportState state = CheckoutReportState.partialSignature}) =>
  CheckoutReportResumeTarget(companyId:company,workerId:notificationWorker,
    workDate:DateTime(2026,10,25), sourceClockInIds:grouped ? const ['10000000-0000-0000-0000-000000000008',notificationClockIn] : const [notificationClockIn],
    clockOutIds:grouped ? const ['10000000-0000-0000-0000-000000000009',notificationClockOut] : const [notificationClockOut],
    sourceClockInId:grouped ? '10000000-0000-0000-0000-000000000008' : notificationClockIn,
    clockOutId:grouped ? '10000000-0000-0000-0000-000000000009' : notificationClockOut,state:state,
    reporterSignatureSaved: bothSigned, responsibleSignatureSaved: bothSigned,
    siteId:notificationSite,reportId:report);
class Resume extends CheckoutReportResumeRepository {
  Resume(super.client);
  bool foreignCompany = false, changedReport = false, grouped = false, bothSigned = false;
  CheckoutReportState state = CheckoutReportState.partialSignature;
  int validations = 0;
  @override Future<List<CheckoutReportResumeTarget>> loadDay({required String workerId, required DateTime workDate}) async =>
    [target(company: foreignCompany ? notificationSite : notificationCompany,grouped:grouped,bothSigned:bothSigned,state:state)];
  @override Future<CheckoutReportResumeTarget> revalidate(CheckoutReportResumeTarget value) async {
    validations++; return target(report: changedReport ? notificationSite : notificationReport,grouped:grouped,bothSigned:bothSigned,state:state);
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
  for(final state in ['source_conflict','report_missing']) {
    testWidgets('$state never starts an editor or fabricates report completion', (t) async {
      source.state = state;await show(t);
      expect(find.text(checkoutReportNotificationLabel(state)),findsOneWidget);
      expect(find.text('対象の日報を再開'),findsNothing);
      expect(find.textContaining('登録に関する未完項目はありません'),findsNothing);
      expect(opened,0);
    });
  }
  testWidgets('both saved signatures on a draft open the exact report for explicit finalization', (t) async {
    source.state = 'signed_projection_unverified'; resume.bothSigned = true;
    await show(t); expect(opened, 0);
    await t.tap(find.text('日報を開く')); await t.pumpAndSettle();
    expect(opened, 1); expect(resume.validations, 2);
  });
  testWidgets('legacy signed projection anomaly remains management-only', (t) async {
    source.state = 'signed_projection_unverified'; resume.bothSigned = true;
    resume.state = CheckoutReportState.signedWithoutAttendance;
    await show(t); await t.tap(find.text('日報を開く')); await t.pumpAndSettle();
    expect(opened, 0); expect(resume.validations, 0);
    expect(find.textContaining('管理者の確認が必要です。自動で再確定しません。'), findsOneWidget);
  });
  testWidgets('deferred source remains informational while genuine pending source opens', (t) async {
    final base = registrationNotification(state: 'reporter_saved_waiting_supervisor');
    final row = Map<String, dynamic>.from((base['items'] as List).single as Map);
    source.envelope = {...base, 'choice_enforcement_enabled': true, 'items': [row,
      {...row, 'source_clock_in_id': notificationSite, 'clock_out_id': notificationCompany,
        'registration_state': 'checkout_deferred', 'blocking': false,
        'choice_available': true, 'member_count': 2, 'report_started': false}]};
    await show(t);
    expect(find.text('対象の日報を再開'), findsOneWidget);
    expect(find.textContaining('退勤のみで記録済みです。'), findsOneWidget);
    await t.tap(find.text('対象の日報を再開')); await t.pumpAndSettle();
    expect(opened, 1);
  });
  for (final legacy in [false, true]) {
    testWidgets('actual HTTP notification and source reader preserve draft versus legacy signed: $legacy', (t) async {
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final calls = <http.Request>[];
      final signature = {'strokes': [[{'x': 1, 'y': 1}]]};
      final actual = SupabaseClient('https://notification-http.invalid', 'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls.add(request);
          final path = request.url.path;
          final Object body;
          if (path.endsWith('/read_checkout_report_registration_notification')) {
            body = registrationNotification(state: 'signed_projection_unverified');
          } else if (path.endsWith('/workers')) {
            body = {'id': notificationWorker, 'company_id': notificationCompany, 'user_id': notificationActor};
          } else if (path.endsWith('/company_members')) {
            body = {'company_id': notificationCompany, 'user_id': notificationActor, 'role': 'employee'};
          } else if (path.endsWith('/attendance_verifications')) {
            body = [for (final isEnd in [false, true]) {
              'id': isEnd ? notificationClockOut : notificationClockIn,
              'company_id': notificationCompany, 'worker_id': notificationWorker,
              'event_type': isEnd ? 'clock_out' : 'clock_in',
              'confirmed_at': isEnd ? '2026-10-25T08:00:00Z' : '2026-10-25T00:00:00Z',
              'work_date': '2026-10-25', 'source_clock_in_id': isEnd ? notificationClockIn : null,
              'site_id': notificationSite, 'route_assignment_id': null,
              'daily_report_id': notificationReport, 'sites': {'name': '実記録fixture現場'}}];
          } else if (path.endsWith('/daily_reports')) {
            body = [{'id': notificationReport, 'company_id': notificationCompany,
              'report_date': '2026-10-25', 'site_id': notificationSite, 'route_assignment_id': null,
              'status': legacy ? 'signed' : 'draft', 'representative_signer_name': 'fixture reporter',
              'supervisor_signer_name': 'fixture supervisor',
              'representative_signature_json': signature, 'supervisor_signature_json': signature}];
          } else if (path.endsWith('/daily_report_workers')) {
            body = [{'report_id': notificationReport, 'worker_id': notificationWorker}];
          } else if (path.endsWith('/attendance_entries') || path.endsWith('/payroll_statements')) {
            body = <Object>[];
          } else {
            throw StateError('Unexpected HTTP fixture path: $path');
          }
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}, request: request);
        }));
      addTearDown(() async {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(actual.dispose);
      });
      Future<void> settleHttp() async {
        // PostgREST decodes through a real isolate. Drive the real event loop
        // until observable loading completes instead of advancing fake time.
        for (var attempt = 0; attempt < 200; attempt++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await t.pump();
          if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
        }
        fail('HTTP fixture did not settle: ${calls.map((request) => request.url.path).toList()}');
      }
      await t.runAsync(() => actual.auth.setInitialSession(jsonEncode({
        'access_token': '${part({'alg': 'HS256'})}.${part({'sub': notificationActor,
          'session_id': notificationClockIn, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
        'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': notificationActor, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}}})));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var routes = 0;
      await t.pumpWidget(MaterialApp(home: CheckoutReportNotificationPage(reportId: notificationReport,
        source: CheckoutReportNotificationRepository(actual),
        resumeRepository: CheckoutReportResumeRepository(actual), opener: (_, value) async {
          routes++; expect(value.reportId, notificationReport);
          expect(value.sourceClockInId, notificationClockIn);
          expect(value.reporterSignatureSaved && value.responsibleSignatureSaved, true);
        })));
      await settleHttp();
      expect(find.text('日報を開く'), findsOneWidget);
      await t.tap(find.text('日報を開く')); await settleHttp();
      expect(routes, legacy ? 0 : 1);
      if (legacy) expect(find.textContaining('管理者の確認が必要です。自動で再確定しません。'), findsOneWidget);
      expect(calls.where((request) => request.method != 'GET').every((request) =>
        request.url.path.endsWith('/read_checkout_report_registration_notification')), true,
        reason: 'Opening saved reporter evidence must not choose/create, sign, finalize or write financial data');
      expect(calls.any((request) => request.url.path.endsWith('/attendance_verifications')), true);
      await t.pumpWidget(const SizedBox.shrink());
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

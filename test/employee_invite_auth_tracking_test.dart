import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/employee_invite_repository.dart';
import 'package:sk_works/features/people/employee_invite_page.dart';
import 'package:sk_works/features/people/employee_initial_registration_page.dart';
import 'employee_invite_context_sdk_test.dart' as fixture;

class TrackingInviteRepository extends EmployeeInviteRepository {
  TrackingInviteRepository(super.client, Stream<AuthState> events)
    : super.forTesting(authEvents: events);
  final completed = Completer<void>();
  final refreshed = Completer<void>();
  int employeeLoads = 0, urlLoads = 0;
  void _loaded() {
    if (employeeLoads >= 2 && urlLoads >= 2 && !refreshed.isCompleted) refreshed.complete();
  }
  @override
  Future<List<InitialRegistrationEmployee>> loadRegisteredEmployees({EmployeeInviteRequest? request}) async {
    final value = await super.loadRegisteredEmployees(request: request);
    employeeLoads++; _loaded(); return value;
  }
  @override
  Future<String> loadTestFlightUrl({EmployeeInviteRequest? request}) async {
    final value = await super.loadTestFlightUrl(request: request);
    urlLoads++; _loaded(); return value;
  }
  Future<EmployeeInviteResult> _completed(Future<EmployeeInviteResult> value) async {
    try { return await value; } finally { if (!completed.isCompleted) completed.complete(); }
  }
  @override
  Future<EmployeeInviteResult> createInvite({required String name, required String phone,
    String requestedRole = 'viewer', bool requestedApprovalAssignee = false,
    String? replaceApprovalAssigneeUserId, EmployeeInviteRequest? request}) => _completed(super.createInvite(
      name: name, phone: phone, requestedRole: requestedRole,
      requestedApprovalAssignee: requestedApprovalAssignee,
      replaceApprovalAssigneeUserId: replaceApprovalAssigneeUserId, request: request));
  @override
  Future<EmployeeInviteResult> createInviteForWorker(String workerId, {required String expectedPhone,
    bool deliverSms = true, EmployeeInviteRequest? request}) => _completed(super.createInviteForWorker(
      workerId, expectedPhone: expectedPhone, deliverSms: deliverSms, request: request));
}


void main() {
  test('unavailable observation denies before SDK reads or invite mutation', () async {
    final f = fixture.Fixture();
    addTearDown(f.client.dispose);
    addTearDown(f.repository.dispose);
    await f.login();
    final r = EmployeeInviteRepository.forTesting(f.client, authEvents: null);
    addTearDown(r.dispose);
    final before = f.requests.length;
    await expectLater(r.beginRequest(), throwsStateError);
    expect(f.requests.length, before);
    expect(f.invokes, 0);
  });
  for (final failure in ['error', 'done']) {
    test('$failure permanently invalidates captured request despite SDK SID ABA', () async {
      final f = fixture.Fixture();
      addTearDown(f.client.dispose);
      addTearDown(f.repository.dispose);
      await f.login();
      final events = StreamController<AuthState>.broadcast();
      addTearDown(() async { if (!events.isClosed) await events.close(); });
      final r = EmployeeInviteRepository.forTesting(f.client, authEvents: events.stream);
      addTearDown(r.dispose);
      final request = await r.beginRequest();
      if (failure == 'error') { events.addError(StateError('synthetic observation failure')); }
      else { await events.close(); }
      await Future<void>.delayed(Duration.zero);
      f.session = fixture.nextSid;
      await f.login();
      f.session = fixture.sid;
      await f.login();
      expect(request.check, throwsStateError);
      await expectLater(r.beginRequest(), throwsStateError);
      expect(f.invokes, 0);
    });
    test('$failure rejects late actual SDK invite response and does not resend', () async {
      final f = fixture.Fixture();
      addTearDown(f.client.dispose);
      addTearDown(f.repository.dispose);
      await f.login();
      final events = StreamController<AuthState>.broadcast();
      addTearDown(() async { if (!events.isClosed) await events.close(); });
      final r = EmployeeInviteRepository.forTesting(f.client, authEvents: events.stream);
      addTearDown(r.dispose);
      final request = await r.beginRequest();
      f.pending = Completer<http.Response>();
      final operation = r.createInvite(name: 'Synthetic Employee', phone: '07000000000', request: request);
      final rejected = expectLater(operation, throwsStateError);
      await f.issued.future;
      if (failure == 'error') { events.addError(StateError('synthetic observation failure')); }
      else { await events.close(); }
      await Future<void>.delayed(Duration.zero);
      f.pending!.complete(http.Response(jsonEncode(fixture.result()), 200,
        headers: {'content-type': 'application/json'}));
      await rejected;
      await expectLater(r.createInvite(name: 'Synthetic Employee', phone: '07000000000', request: request), throwsStateError);
      expect(f.invokes, 1);
    });
  }
  for (final initialPage in [false, true]) {
    for (final failure in ['error', 'done']) {
      testWidgets('displayed credentials are removed on $failure, initialPage=$initialPage', (tester) async {
        final f = (await tester.runAsync(() async => fixture.Fixture()))!;
        final events = (await tester.runAsync(() async => StreamController<AuthState>.broadcast()))!;
        late TrackingInviteRepository repository;
        addTearDown(() async {
          await tester.runAsync(() async {
            await repository.dispose();
            if (!events.isClosed) await events.close();
            await f.close();
          });
        });
        await tester.runAsync(f.login);
        repository = TrackingInviteRepository(f.client, events.stream);
        await tester.pumpWidget(MaterialApp(home: initialPage
          ? EmployeeInitialRegistrationPage(repository: repository)
          : EmployeeInvitePage(repository: repository)));
        await tester.pumpAndSettle();
        if (initialPage) {
          await tester.ensureVisible(find.text('送信'));
          await tester.runAsync(() async {
            await tester.tap(find.text('送信'));
            await repository.completed.future;
            await repository.refreshed.future;
          });
        } else {
          await tester.enterText(find.byType(TextField).at(0), 'Synthetic Employee');
          await tester.enterText(find.byType(TextField).at(1), '07000000000');
          final create = find.byWidgetPredicate((w) => w is FilledButton);
          await tester.ensureVisible(create.first);
          await tester.runAsync(() async { await tester.tap(create.first); await repository.completed.future; });
        }
        await tester.pumpAndSettle();
        final credential = initialPage ? '初期パスワード: ${fixture.fixturePassword}' : fixture.fixturePassword;
        if (initialPage) {
          await tester.scrollUntilVisible(find.text(credential), 200, maxScrolls: 20,
            scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first);
        }
        expect(find.text(credential), findsOneWidget);
        await tester.runAsync(() async {
          if (failure == 'error') { events.addError(StateError('synthetic tracking failure')); }
          // UI listeners run in the widget zone. Pump that zone before waiting
          // for close completion; awaiting it inside runAsync deadlocks delivery.
          else { unawaited(events.close()); }
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.text(credential), findsNothing);
        expect(find.text('ログイン状態または会社が変わりました。画面を開き直してください。'), findsOneWidget);
        expect(f.invokes, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

}

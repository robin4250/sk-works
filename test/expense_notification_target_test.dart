import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/expenses/expense_notification_page.dart';
import 'package:sk_works/features/notifications/notification_target_policy.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notification_business_status.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';

const notice = '10000000-0000-4000-8000-000000000001';
const claimId = '20000000-0000-4000-8000-000000000002';
const command = '30000000-0000-4000-8000-000000000003';
const company = '40000000-0000-4000-8000-000000000004';

Map<String, dynamic> row({bool completed = false}) => {
  'notification_id': notice,
  'action_key': completed
      ? 'expense_review_completed'
      : 'expense_review_request',
  'action_id': completed ? command : claimId,
  'company_id': company,
  'claim_id': claimId,
  'claim': <String, dynamic>{
    'id': claimId,
    'company_id': company,
    'revision': 2,
    'applicant_name': 'Saved applicant',
    'description': 'Saved expense',
    'amount_yen': 1200,
    'incurred_on': '2026-10-01',
    'submitted_at': '2026-10-02T01:00:00Z',
    'approval': completed ? 'approved' : 'pending',
    'allocation': completed ? 'customer' : 'unallocated',
    'counterparty_name': completed ? 'Saved customer' : null,
    'settlement_method': completed ? 'payroll' : null,
    'settlement_month': completed ? '2026-10-01' : null,
  },
};

class Source implements ExpenseNoticeSource {
  @override
  String? actor = 'actor-a';
  final changes = StreamController<String?>.broadcast(sync: true);
  @override
  Stream<String?> get actorChanges => changes.stream;
  Future<Map<String, dynamic>?> Function() read = () async => row();
  final ids = <String>[];
  @override
  Future<Map<String, dynamic>?> load(String id) {
    ids.add(id);
    return read();
  }
}

Future<void> show(
  WidgetTester tester,
  Source source, {
  bool completed = false,
  String notificationId = notice,
  String? actionId,
}) => tester.pumpWidget(
  MaterialApp(
    home: ExpenseNotificationPage(
      notificationId: notificationId,
      actionKey: completed
          ? 'expense_review_completed'
          : 'expense_review_request',
      actionId: actionId ?? (completed ? command : claimId),
      source: source,
    ),
  ),
);

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'request shows only saved target and never offers approval or payment',
    (tester) async {
      final source = Source();
      await show(tester, source);
      await tester.pumpAndSettle();
      expect(source.ids, [notice]);
      expect(find.text('Saved applicant'), findsOneWidget);
      expect(find.text('Saved expense'), findsOneWidget);
      expect(find.text('1200円'), findsOneWidget);
      expect(find.text('承認: 承認待ち'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '承認'), findsNothing);
      expect(find.text(notice), findsNothing);
      expect(find.text(claimId), findsNothing);
    },
  );

  testWidgets(
    'completion keeps immutable receipt identity distinct from claim UUID',
    (tester) async {
      final source = Source()..read = () async => row(completed: true);
      await show(tester, source, completed: true);
      await tester.pumpAndSettle();
      expect(find.text('Saved customer'), findsOneWidget);
      expect(find.text('精算方法: 給与精算'), findsOneWidget);
      expect(find.textContaining('通知作成時の確定内容'), findsOneWidget);
      expect(source.ids, [notice]);
      expect(find.text(command), findsNothing);
    },
  );

  for (final bad in ['', 'invalid', '$notice ']) {
    testWidgets('invalid notice $bad performs no request', (tester) async {
      final source = Source();
      await show(tester, source, notificationId: bad);
      await tester.pumpAndSettle();
      expect(source.ids, isEmpty);
      expect(find.text('Saved expense'), findsNothing);
      expect(find.textContaining('対象の経費申請を表示できません'), findsOneWidget);
    });
  }

  for (final field in [
    'notification_id',
    'action_id',
    'action_key',
    'company',
    'claim',
    'amount',
    'zero',
    'unallocated',
    'date',
    'method',
    'allocation',
  ]) {
    testWidgets(
      'mismatched or malformed $field never renders confidential response',
      (tester) async {
        final value = row(completed: true);
        final data = value['claim'] as Map<String, dynamic>;
        switch (field) {
          case 'notification_id':
            value[field] = command;
          case 'action_id':
            value[field] = claimId;
          case 'action_key':
            value[field] = 'expense_review_request';
          case 'company':
            data['company_id'] = notice;
          case 'claim':
            data['id'] = notice;
          case 'amount':
            data['amount_yen'] = '1200';
          case 'zero':
            data['amount_yen'] = 0;
          case 'unallocated':
            data['allocation'] = 'unallocated';
          case 'date':
            data['incurred_on'] = '2026-02-30';
          case 'method':
            data['settlement_method'] = 'unknown';
          case 'allocation':
            data['counterparty_name'] = null;
        }
        final source = Source()..read = () async => value;
        await show(tester, source, completed: true);
        await tester.pumpAndSettle();
        expect(find.text('Saved expense'), findsNothing);
        expect(find.text('1200円'), findsNothing);
        expect(find.textContaining('対象の経費申請を表示できません'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final fail in [false, true]) {
    testWidgets(
      'late old actor result is discarded even after ABA, error=$fail',
      (tester) async {
        final pending = Completer<Map<String, dynamic>?>();
        final source = Source()..read = () => pending.future;
        await show(tester, source);
        source.actor = 'actor-b';
        source.changes.add(source.actor);
        source.actor = 'actor-a';
        source.changes.add(source.actor);
        if (fail) {
          pending.completeError(StateError('private response error'));
        } else {
          pending.complete(row());
        }
        await tester.pumpAndSettle();
        expect(find.text('Saved expense'), findsNothing);
        expect(find.textContaining('private response error'), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '再読み込み'),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'background clears values and same actor resume reloads exact notice',
    (tester) async {
      final source = Source();
      await show(tester, source);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('Saved expense'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(source.ids, [notice, notice]);
      expect(find.text('Saved expense'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposed request cannot restore a confidential result', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>?>();
    final source = Source()..read = () => pending.future;
    await show(tester, source);
    await tester.pumpWidget(const SizedBox());
    pending.complete(row());
    await tester.pumpAndSettle();
    expect(find.text('Saved expense'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing or denied target stays closed without RPC fallback', (
    tester,
  ) async {
    final source = Source()..read = () async => null;
    await show(tester, source);
    await tester.pumpAndSettle();
    expect(find.text('Saved expense'), findsNothing);
    source.read = () async => throw StateError('private denied details');
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(source.ids, [notice, notice]);
    expect(find.textContaining('private denied details'), findsNothing);
    expect(find.text('Saved expense'), findsNothing);
  });

  test('both new actions require their exact saved UUID', () {
    for (final action in [
      'expense_review_request',
      'expense_review_completed',
    ]) {
      expect(notificationTargetIsValid(action, claimId), true);
      for (final bad in [null, '', 'invalid', '$claimId ']) {
        expect(notificationTargetIsValid(action, bad), false);
      }
    }
  });

  test('notification routes retain saved notice and action identities', () {
    for (final completed in [false, true]) {
      final item = AppNotificationRecord(id: notice, kind: 'approval', title: 'Expense', body: '',
        createdAt: DateTime(2026, 10, 1), read: false,
        actionKey: completed ? 'expense_review_completed' : 'expense_review_request',
        actionId: completed ? command : claimId);
      final page = notificationDestination(item) as ExpenseNotificationPage;
      expect(page.notificationId, notice);
      expect(page.actionId, item.actionId);
      expect(page.actionKey, item.actionKey);
      expect(item.hasBusinessTarget, !completed);
    }
  });

  test('only validated current requests contribute a business status', () {
    for (final status in ['pending','approved','rejected']) {
      final value = row();
      (value['claim'] as Map)['approval'] = status;
      if (status == 'approved') {
        (value['claim'] as Map<String, dynamic>).addAll({'allocation': 'ownCompany', 'settlement_method': 'cash', 'settlement_month': '2026-10-01'});
      }
      expect(expenseNotificationBusinessStatus(notificationId: notice, claimId: claimId, value: value).state,
        switch (status) {'pending' => NotificationBusinessState.pending,
          'approved' => NotificationBusinessState.completed, _ => NotificationBusinessState.rejected});
    }
    for (final value in [null, row(completed: true), row()..['claim_id'] = command,
      row()..['claim'] = <String, dynamic>{'approval':'pending'}]) {
      expect(expenseNotificationBusinessStatus(notificationId: notice, claimId: claimId, value: value).state,
        NotificationBusinessState.unknown);
    }
  });

  test('approval alone does not finish the allocation notification task', () {
    for (final field in ['allocation', 'settlement_method']) {
      final value = row();
      final data = value['claim'] as Map<String, dynamic>;
      data.addAll({'approval': 'approved', 'allocation': 'ownCompany', 'settlement_method': 'cash', 'settlement_month': '2026-10-01'});
      data[field] = field == 'allocation' ? 'unallocated' : null;
      expect(expenseNotificationBusinessStatus(notificationId: notice, claimId: claimId, value: value).state,
        NotificationBusinessState.pending);
    }
  });

  testWidgets('actor stream error clears previously displayed data', (tester) async {
    final source = Source();
    await show(tester, source); await tester.pumpAndSettle();
    expect(find.text('Saved expense'), findsOneWidget);
    source.changes.addError(StateError('fixture stream error'));
    await tester.pumpAndSettle();
    expect(find.text('Saved expense'), findsNothing);
    expect(find.textContaining('fixture stream error'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('missing SDK reader fails without a second endpoint or write fallback', () async {
    var calls = 0;
    final client = SupabaseClient('https://expense-notice-fixture.invalid', 'public_fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(jsonEncode({'code':'PGRST202','message':'fixture reader missing'}), 404,
          request: request, headers: {'content-type':'application/json'});
      }));
    addTearDown(client.dispose);
    await expectLater(SupabaseExpenseNoticeSource(client).load(notice), throwsA(isA<PostgrestException>()));
    expect(calls, 1);
  });

  test(
    'actual SDK sends one read RPC with only the notification UUID',
    () async {
      final calls = <http.Request>[];
      final client = SupabaseClient(
        'https://expense-notice-fixture.invalid',
        'public_fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode(row()),
            200,
            headers: {'content-type': 'application/json'}, request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await SupabaseExpenseNoticeSource(client).load(notice);
      expect(result!['claim_id'], claimId);
      expect(calls, hasLength(1));
      expect(calls.single.url.origin, 'https://expense-notice-fixture.invalid');
      expect(calls.single.url.path, '/rest/v1/rpc/expense_notification_target');
      expect(calls.single.method, 'POST');
      expect(jsonDecode(calls.single.body), {'p_notification_id': notice});
    },
  );
}

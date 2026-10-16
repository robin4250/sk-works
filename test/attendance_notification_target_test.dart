import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_notification_page.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';
import 'package:sk_works/features/notifications/notifications_page.dart';

const id = '11111111-1111-1111-1111-111111111111';
Map<String, dynamic> row([String value = id]) => {
  'id': value, 'company_id': 'company', 'worker_id': 'worker',
  'event_type': 'clock_in', 'confirmed_at': '2026-09-01T16:30:00Z',
  'workers': {'name': '通知の社員'}, 'sites': {'name': '対象現場'},
};
class Source implements AttendanceNoticeSource {
  @override
  String? actor = 'actor';
  final changes = StreamController<String?>.broadcast();
  @override
  Stream<String?> get actorChanges => changes.stream;
  Map<String, dynamic>? record = row();
  List<Map<String, dynamic>> rows = [row('22222222-2222-2222-2222-222222222222'), row()];
  Completer<Map<String, dynamic>?>? pending;
  bool fail = false;
  int calls = 0;
  DateTime? start;
  DateTime? end;
  String? company;
  @override
  Future<Map<String, dynamic>?> target(String id) async {
    calls++;
    if (fail) throw Exception('permission denied');
    return pending == null ? record : pending!.future;
  }
  @override
  Future<List<Map<String, dynamic>>> day(String company, DateTime start, DateTime end) async {
    this.company = company; this.start = start; this.end = end;
    return rows;
  }
  void change(String? value) { actor = value; changes.add(value); }
}
void main() {
  test('notification preserves the verification ID; missing ID does not become today', () {
    AppNotificationRecord notice(String? target) => AppNotificationRecord(
      id: 'notice', kind: 'attendance', title: '', body: '',
      createdAt: DateTime(2026), read: false, actionKey: 'attendance_today', actionId: target);
    expect((notificationDestination(notice(id)) as AttendanceNotificationPage).verificationId, id);
    expect((notificationDestination(notice(null)) as AttendanceNotificationPage).verificationId, '');
  });
  Future<void> open(WidgetTester tester, Source source, {String target = id}) async {
    await tester.pumpWidget(MaterialApp(home: AttendanceNotificationPage(verificationId: target, source: source)));
    await tester.pumpAndSettle();
  }
  testWidgets('opens original JST day and exact highlighted event first', (tester) async {
    final source = Source(); addTearDown(source.changes.close);
    await open(tester, source);
    expect(find.text('2026/9/2 の出勤記録'), findsOneWidget);
    expect(source.start, DateTime.utc(2026, 9, 1, 15));
    expect(source.end, DateTime.utc(2026, 9, 2, 15));
    expect(source.company, 'company');
    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards.first.key, const ValueKey('verification-$id'));
    expect(cards.first.color, isNotNull);
    expect(cards.last.color, isNull);
    expect(find.text('通知の対象：通知の社員'), findsOneWidget);
  });
  testWidgets('invalid ID is rejected before any query', (tester) async {
    final source = Source(); addTearDown(source.changes.close);
    await open(tester, source, target: '');
    expect(source.calls, 0);
    expect(find.text('通知の出勤記録IDが正しくありません。'), findsOneWidget);
  });
  testWidgets('deleted or inaccessible target has no today fallback', (tester) async {
    final source = Source()..record = null; addTearDown(source.changes.close);
    await open(tester, source);
    expect(find.text('対象の出勤記録は削除されたか、閲覧権限がありません。'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
  testWidgets('query rejection offers retry without exposing rows', (tester) async {
    final source = Source()..fail = true; addTearDown(source.changes.close);
    await open(tester, source);
    expect(find.text('出勤記録を読み込めません。接続または閲覧権限を確認して再試行してください。'), findsOneWidget);
    source.fail = false;
    await tester.tap(find.text('再読み込み')); await tester.pumpAndSettle();
    expect(find.text('通知の対象：通知の社員'), findsOneWidget);
  });
  testWidgets('target disappearing between requests fails closed', (tester) async {
    final source = Source()..rows = []; addTearDown(source.changes.close);
    await open(tester, source);
    expect(find.text('対象の出勤記録が変更されたか、閲覧できなくなりました。再読み込みしてください。'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });
  testWidgets('actor switch hides loaded data and returning actor does not restore it', (tester) async {
    final source = Source(); addTearDown(source.changes.close);
    await open(tester, source);
    source.change('other'); await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    source.change('actor'); await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(find.text('再読み込み'), findsNothing);
  });
  testWidgets('delayed response cannot publish after actor changed', (tester) async {
    final source = Source()..pending = Completer(); addTearDown(source.changes.close);
    await tester.pumpWidget(MaterialApp(home: AttendanceNotificationPage(verificationId: id, source: source)));
    source.change(null); await tester.pump();
    source.pending!.complete(row()); await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(find.text('ログイン状態が変わりました。通知一覧から開き直してください。'), findsOneWidget);
  });
}

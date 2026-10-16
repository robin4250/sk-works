import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/attendance_update_badge_repository.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/notifications/app_notification_repository.dart';

const first = '10000000-0000-0000-0000-000000000001';
const second = '10000000-0000-0000-0000-000000000002';
const third = '10000000-0000-0000-0000-000000000003';
final clock = DateTime.parse('2026-10-16T03:00:00Z');
AppNotificationRecord notice(String id, String source, {String action = 'attendance_today', bool read = false}) =>
  AppNotificationRecord(id: id, kind: 'attendance', title: '', body: '',
    createdAt: clock.subtract(const Duration(minutes: 1)), read: read,
    actionKey: action, actionId: source);

class Fixture {
  String? actor = 'actor';
  DateTime time = clock;
  bool failingLoad = false;
  bool saving = true;
  final Map<String, List<String>> saved = {};
  List<AppNotificationRecord> notices = [notice('n1', first)];
  List<Map<String, dynamic>> rows = [
    {'id': first, 'company_id': 'company', 'event_type': 'clock_in', 'confirmed_at': '2026-10-16T01:00:00Z'},
  ];
  late final repository = AttendanceUpdateBadgeRepository(
    currentActor: () => actor,
    loadUnread: () async {
      if (failingLoad) throw StateError('offline');
      return notices;
    },
    loadSources: (company, ids) async => rows,
    readSeen: (key) async => saved[key] ?? [],
    writeSeen: (key, ids) async {
      if (!saving) return false;
      saved[key] = ids;
      return true;
    },
    now: () => time,
  );
  AttendanceBadgeScope get scope => AttendanceBadgeScope('actor', 'company', attendanceBadgeJstDate(time));
}

void main() {
  test('JST date uses exact midnight rather than device UTC day', () {
    expect(attendanceBadgeJstDate(DateTime.parse('2026-10-15T14:59:59Z')), '2026-10-15');
    expect(attendanceBadgeJstDate(DateTime.parse('2026-10-15T15:00:00Z')), '2026-10-16');
  });
  test('counts exact source IDs once, excludes unrelated and already read notices', () async {
    final f = Fixture();
    f.notices = [notice('n1', first), notice('n2', first),
      notice('n3', second, action: 'site_map'), notice('n4', third, read: true)];
    expect((await f.repository.load(f.scope)).count, 1);
  });
  test('only same company and JST work date clock-in sources count', () async {
    final f = Fixture();
    f.notices = [notice('n1', first), notice('n2', second), notice('n3', third)];
    f.rows = [
      {'id': first, 'company_id': 'other', 'event_type': 'clock_in', 'confirmed_at': '2026-10-16T01:00:00Z'},
      {'id': second, 'company_id': 'company', 'event_type': 'clock_in', 'confirmed_at': '2026-10-15T14:59:00Z'},
      {'id': third, 'company_id': 'company', 'event_type': 'clock_out', 'confirmed_at': '2026-10-16T01:00:00Z'},
    ];
    expect((await f.repository.load(f.scope)).count, 0);
  });
  test('acknowledges snapshot only and leaves updates arriving during open', () async {
    final f = Fixture();
    final before = await f.repository.load(f.scope);
    f.notices.add(notice('new', second));
    f.rows.add({'id': second, 'company_id': 'company', 'event_type': 'clock_in', 'confirmed_at': '2026-10-16T02:00:00Z'});
    await f.repository.acknowledge(before, clock);
    final after = await f.repository.load(f.scope);
    expect(after.pendingSourceIds, {second});
    f.notices.add(notice('duplicate-after-read', first));
    expect((await f.repository.load(f.scope)).pendingSourceIds, {second});
  });
  test('failed load is an error, not an empty successful snapshot', () async {
    final f = Fixture();
    final before = await f.repository.load(f.scope);
    f.failingLoad = true;
    await expectLater(f.repository.load(f.scope), throwsStateError);
    expect(before.count, 1);
  });
  test('failed acknowledgement preserves unseen event and snapshot', () async {
    final f = Fixture();
    final before = await f.repository.load(f.scope);
    f.saving = false;
    await expectLater(f.repository.acknowledge(before, clock), throwsStateError);
    expect(before.count, 1);
    expect((await f.repository.load(f.scope)).count, 1);
  });
  test('actor, company, day and post-open snapshot stay isolated', () async {
    final f = Fixture();
    final old = await f.repository.load(f.scope);
    expect(f.scope.storageKey, isNot(const AttendanceBadgeScope('actor', 'other', '2026-10-16').storageKey));
    f.actor = 'other';
    await expectLater(f.repository.acknowledge(old, clock), throwsStateError);
    f.actor = 'actor';
    await expectLater(f.repository.acknowledge(old, clock.subtract(const Duration(seconds: 1))), throwsStateError);
    f.time = DateTime.parse('2026-10-16T15:00:00Z');
    await expectLater(f.repository.acknowledge(old, f.time), throwsStateError);
    expect((await f.repository.load(f.scope)).count, 0);
  });
  testWidgets('red count shows update count and zero/unavailable hide count', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AttendanceUpdateCountBadge(count: 3))));
    expect(find.text('3'), findsOneWidget);
    final box = tester.widget<Container>(find.byKey(const ValueKey('attendance-update-count')));
    expect((box.decoration as BoxDecoration).color, Colors.red);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AttendanceUpdateCountBadge(count: 0))));
    expect(find.byKey(const ValueKey('attendance-update-count')), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AttendanceUpdateCountBadge(count: null))));
    expect(find.byKey(const ValueKey('attendance-update-count')), findsNothing);
  });
}

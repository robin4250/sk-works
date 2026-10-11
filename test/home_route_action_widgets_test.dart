import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/home/home_route_action_state.dart';

void main() {
  Widget home(
    HomeRouteActionState state,
    List<String> opened, {
    HomeAttendancePhase phase = HomeAttendancePhase.working,
    bool pending = false,
    bool pendingReports = false,
    bool showAttendanceReport = true,
    bool modulesEnabled = true,
    bool optionalClockInAllowed = true,
    String? routeId = 'route',
    String? selectedRouteId,
    String? selectedRouteName,
    String? siteName,
    int shiftCount = 1,
  }) => MaterialApp(
    home: Scaffold(
      body: FriendlyHomeContent(
        identity: const HomeIdentity(
          role: 'member',
          companyName: '会社',
          displayName: '本人',
        ),
        requiredDocumentAttention: const RequiredDocumentAttention(
          missingCount: 0,
          missingNames: [],
          needsLicense: false,
          needsQualification: false,
        ),
        moduleEnabled: (_) => modulesEnabled,
        showAttendanceReport: showAttendanceReport,
        visibleHomeKeys: const {'attendance_verify'},
        showTodayAttendance: false,
        attendanceStatus: HomeAttendanceStatus(
          phase: phase,
          selectedRouteId: selectedRouteId,
          selectedRouteName: selectedRouteName,
          siteName: siteName,
          openShifts: List.generate(
            shiftCount,
            (index) => AttendanceShiftContext(
              id: 'shift-$index',
              workerId: 'worker',
              workDate: DateTime(2026, 10, 11),
              clockIn: DateTime(2026, 10, 11, 9),
              verificationMode: 'manual',
              routeId: routeId,
            ),
          ),
        ),
        routeActionState: state,
        optionalClockInAllowed: optionalClockInAllowed,
        hasPendingRouteRecord: pending,
        hasPendingRouteReports: pendingReports,
        onOpen: (key) async {
          opened.add(key);
        },
        onRefresh: () async {},
      ),
    ),
  );

  testWidgets(
    'completed route disables arrival but keeps intermediate checkout',
    (tester) async {
      final ws = <String, dynamic>{
        'source_clock_in_id': 'shift-0',
        'visit_contract_version': 1,
        'enabled': true,
        'is_open': true,
        'work_date': '2026-10-11',
        'stops': [
          for (var i = 0; i < 3; i++) {'id': 'stop-$i'},
        ],
        'visits': <Map<String, dynamic>>[],
      };
      final opened = <String>[];
      ButtonStyleButton action(String text) => tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(
          home(homeRouteActionState(ws, 'shift-0'), opened),
        );
        await tester.pumpAndSettle();
        expect(action('現場到着').onPressed, isNotNull);
        expect(action('退勤').onPressed, isNotNull);
        final visit = <String, dynamic>{
          'start_capture_id': 'start-$i',
          'route_stop_id': 'stop-$i',
          'work_date': '2026-10-11',
          'started_at': '2026-10-11T09:00:00+09:00',
          'end_capture_id': null,
          'ended_at': null,
        };
        (ws['visits'] as List).add(visit);
        await tester.pumpWidget(
          home(homeRouteActionState(ws, 'shift-0'), opened),
        );
        await tester.pumpAndSettle();
        expect(action('現場移動').onPressed, isNotNull);
        visit['end_capture_id'] = 'end-$i';
        visit['ended_at'] = '2026-10-11T10:00:00+09:00';
      }
      await tester.pumpWidget(
        home(homeRouteActionState(ws, 'shift-0'), opened),
      );
      await tester.pumpAndSettle();
      expect(action('現場到着').onPressed, isNull);
      expect(action('現場移動').onPressed, isNull);
      expect(action('退勤').onPressed, isNotNull);
      await tester.pumpWidget(
        home(
          HomeRouteActionState.unavailable,
          opened,
          phase: HomeAttendancePhase.unknown,
          optionalClockInAllowed: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(action('出勤').onPressed, isNull);
      expect(action('退勤').onPressed, isNull);
    },
  );

  testWidgets(
    'Master OFF prevents new optional clock-in but preserves the active route',
    (tester) async {
      final opened = <String>[];
      ButtonStyleButton action(String label) =>
          tester.widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            ),
          );
      await tester.pumpWidget(
        home(
          HomeRouteActionState.unavailable,
          opened,
          phase: HomeAttendancePhase.notStarted,
          shiftCount: 0,
          selectedRouteId: 'route',
          optionalClockInAllowed: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(action('出勤').onPressed, isNull);
      expect(opened, isEmpty);
      await tester.pumpWidget(
        home(
          HomeRouteActionState.arrive,
          opened,
          optionalClockInAllowed: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(action('現場到着').onPressed, isNotNull);
      expect(action('退勤').onPressed, isNotNull);
      expect(action('現場移動').onPressed, isNull);
    },
  );

  testWidgets('only confirmed next route action is enabled', (tester) async {
    final opened = <String>[];
    for (final state in HomeRouteActionState.values) {
      await tester.pumpWidget(home(state, opened));
      await tester.pumpAndSettle();
      final arrival = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('現場到着'),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        ),
      );
      final move = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('現場移動'),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        ),
      );
      expect(arrival.onPressed != null, state == HomeRouteActionState.arrive);
      expect(move.onPressed != null, state == HomeRouteActionState.move);
      if (state != HomeRouteActionState.unavailable) {
        final label = state == HomeRouteActionState.arrive ? '現場到着' : '現場移動';
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        expect(
          opened.last,
          state == HomeRouteActionState.arrive
              ? 'route_visit_arrive'
              : 'route_visit_move',
        );
      }
    }
  });

  testWidgets(
    'finished route shift hides actions while recovery remains reachable',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        home(
          HomeRouteActionState.arrive,
          opened,
          phase: HomeAttendancePhase.finished,
          pending: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('現場到着'), findsNothing);
      expect(find.text('現場移動'), findsNothing);
      await tester.ensureVisible(find.text('保留記録を再確認'));
      await tester.tap(find.text('保留記録を再確認'));
      expect(opened, ['route_visit_recover']);
    },
  );
  testWidgets(
    'pending visit report survives hidden attendance and disabled module',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        home(
          HomeRouteActionState.unavailable,
          opened,
          phase: HomeAttendancePhase.finished,
          pendingReports: true,
          showAttendanceReport: false,
          modulesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('現場別日報を再開'), findsOneWidget);
      await tester.tap(find.text('現場別日報を再開'));
      expect(opened, ['route_visit_recover']);
    },
  );

  testWidgets(
    'ordinary, selected-only and ambiguous shifts hide route actions',
    (tester) async {
      final opened = <String>[];
      for (final scenario in [
        home(HomeRouteActionState.arrive, opened, routeId: null),
        home(
          HomeRouteActionState.arrive,
          opened,
          phase: HomeAttendancePhase.notStarted,
          selectedRouteId: 'route',
          shiftCount: 0,
        ),
        home(HomeRouteActionState.arrive, opened, shiftCount: 0),
        home(HomeRouteActionState.arrive, opened, shiftCount: 2),
      ]) {
        await tester.pumpWidget(scenario);
        await tester.pumpAndSettle();
        expect(find.text('現場到着'), findsNothing);
        expect(find.text('現場移動'), findsNothing);
        expect(find.text('出勤'), findsOneWidget);
        expect(find.text('退勤'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'unknown active route contract stays disabled with a status check',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(home(HomeRouteActionState.unavailable, opened));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('現場記録の状態を確認'));
      await tester.tap(find.text('現場記録の状態を確認'));
      expect(opened, ['route_visit']);
    },
  );
  testWidgets(
    'route destination hides the site label; ordinary attendance retains it',
    (tester) async {
      await tester.pumpWidget(
        home(
          HomeRouteActionState.unavailable,
          [],
          phase: HomeAttendancePhase.notStarted,
          shiftCount: 0,
          selectedRouteId: 'route',
          selectedRouteName: '江戸川→東京海上',
          siteName: '江戸川→東京海上',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('選択中の現場：江戸川→東京海上'), findsNothing);
      expect(find.text('選択中のルート：江戸川→東京海上'), findsOneWidget);
      await tester.pumpWidget(
        home(
          HomeRouteActionState.unavailable,
          [],
          routeId: null,
          siteName: '江戸川',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('選択中の現場：江戸川'), findsOneWidget);
    },
  );

  testWidgets('unavailable clock actions are truly disabled and gray', (
    tester,
  ) async {
    final opened = <String>[];
    for (final phase in HomeAttendancePhase.values) {
      await tester.pumpWidget(
        home(
          HomeRouteActionState.unavailable,
          opened,
          phase: phase,
          routeId: null,
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['出勤', '退勤']) {
        final finder = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        );
        final button = tester.widget<ButtonStyleButton>(finder);
        final enabled = label == '出勤'
            ? phase == HomeAttendancePhase.notStarted
            : phase == HomeAttendancePhase.working;
        expect(button.onPressed != null, enabled);
        if (!enabled) {
          final context = tester.element(finder);
          expect(
            button.style!.foregroundColor!.resolve({WidgetState.disabled}),
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
          );
          expect(
            button.style!.side!.resolve({WidgetState.disabled})!.color,
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
          );
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
        }
      }
    }
    expect(opened, isEmpty);
  });
}

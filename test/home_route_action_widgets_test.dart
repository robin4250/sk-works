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
    String? routeId = 'route',
    String? selectedRouteId,
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
        moduleEnabled: (_) => true,
        visibleHomeKeys: const {'attendance_verify'},
        showTodayAttendance: false,
        attendanceStatus: HomeAttendanceStatus(
          phase: phase,
          selectedRouteId: selectedRouteId,
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
        hasPendingRouteRecord: pending,
        onOpen: (key) async {
          opened.add(key);
        },
        onRefresh: () async {},
      ),
    ),
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
}

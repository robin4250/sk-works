import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/attendance/attendance_verification_repository.dart';
import '../lib/features/home/friendly_home_content.dart';
import '../lib/features/home/home_attention_repository.dart';
import '../lib/features/home/home_membership_repository.dart';
import '../lib/features/home/home_route_action_state.dart';

void main() {
  Widget home(
    HomeRouteActionState state,
    List<String> opened, {
    HomeAttendancePhase phase = HomeAttendancePhase.working,
    bool pending = false,
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
        attendanceStatus: HomeAttendanceStatus(phase: phase),
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
    }
  });

  testWidgets(
    'finished and unknown records disable both actions while recovery remains reachable',
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
      for (final label in ['現場到着', '現場移動']) {
        expect(
          tester
              .widget<ButtonStyleButton>(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is ButtonStyleButton,
                  ),
                ),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.ensureVisible(find.text('保留記録を再確認'));
      await tester.tap(find.text('保留記録を再確認'));
      expect(opened, ['route_visit_recover']);
    },
  );
}

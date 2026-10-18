import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_correction_approval_repository.dart';
import 'package:sk_works/features/attendance/attendance_correction_approvals_page.dart';

const target = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
AttendanceCorrectionApprovalRequest row(String id, String name) =>
    AttendanceCorrectionApprovalRequest(
      id: id,
      requestedBy: 'synthetic-user',
      requestedByName: name,
      itemCount: 1,
      signerName: '',
      submittedAt: DateTime(2026, 10, 1),
    );
final rows = [row(other, 'Other request'), row(target, 'Target request')];

Future<void> open(
  WidgetTester tester,
  String? id,
  Future<List<AttendanceCorrectionApprovalRequest>> Function() loader,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AttendanceCorrectionApprovalsPage(
        initialRequestId: id,
        loadRequests: loader,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('ordinary inbox retains authorized requests in original order', (
    tester,
  ) async {
    await open(tester, null, () async => rows);
    await tester.pumpAndSettle();
    expect(find.text('Other request'), findsOneWidget);
    expect(find.text('Target request'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Other request')).dy,
      lessThan(tester.getTopLeft(find.text('Target request')).dy),
    );
  });

  testWidgets('notification displays only its exact saved request', (
    tester,
  ) async {
    await open(tester, target, () async => rows);
    await tester.pumpAndSettle();
    expect(find.text('Target request'), findsOneWidget);
    expect(find.text('Other request'), findsNothing);
  });

  for (final id in [
    '',
    ' ',
    'bad-id',
    '$target ',
    '33333333-3333-4333-8333-333333333333',
  ]) {
    testWidgets('unavailable target $id never falls back to the inbox', (
      tester,
    ) async {
      await open(tester, id, () async => rows);
      await tester.pumpAndSettle();
      expect(find.text('対象の申請は完了済み、または閲覧できません。'), findsOneWidget);
      expect(find.text('Other request'), findsNothing);
      expect(find.text('Target request'), findsNothing);
    });
  }

  for (final failOld in [false, true]) {
    testWidgets('target change rejects old response, failure=$failOld', (
      tester,
    ) async {
      final old = Completer<List<AttendanceCorrectionApprovalRequest>>();
      await open(tester, target, () => old.future);
      await open(tester, other, () async => rows);
      await tester.pumpAndSettle();
      expect(find.text('Other request'), findsOneWidget);
      if (failOld) {
        old.completeError(StateError('old request failure'));
      } else {
        old.complete(rows);
      }
      await tester.pumpAndSettle();
      expect(find.text('Other request'), findsOneWidget);
      expect(find.text('Target request'), findsNothing);
      expect(find.textContaining('old request failure'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'changing a loaded target clears its row before a new read completes',
    (tester) async {
      await open(tester, target, () async => rows);
      await tester.pumpAndSettle();
      final next = Completer<List<AttendanceCorrectionApprovalRequest>>();
      await open(tester, other, () => next.future);
      expect(find.text('Target request'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      next.complete(rows);
      await tester.pumpAndSettle();
      expect(find.text('Other request'), findsOneWidget);
    },
  );

  testWidgets('disposed late read never publishes rows', (tester) async {
    final pending = Completer<List<AttendanceCorrectionApprovalRequest>>();
    await open(tester, target, () => pending.future);
    await tester.pumpWidget(const SizedBox());
    pending.complete(rows);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Target request'), findsNothing);
  });
  for (final failOld in [false, true]) {
    testWidgets(
      'late detail read cannot open an old target dialog, failure=$failOld',
      (tester) async {
        final oldDetails = Completer<List<AttendanceCorrectionApprovalItem>>();
        Future<List<AttendanceCorrectionApprovalItem>> details(String id) =>
            id == target ? oldDetails.future : Future.value([]);
        Future<void> show(String id) async {
          await tester.pumpWidget(
            MaterialApp(
              home: AttendanceCorrectionApprovalsPage(
                initialRequestId: id,
                loadRequests: () async => rows,
                loadRequestItems: details,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(target);
        await show(other);
        expect(find.text('Other request / 1件'), findsOneWidget);
        if (failOld) {
          oldDetails.completeError(StateError('old detail failure'));
        } else {
          oldDetails.complete([]);
        }
        await tester.pumpAndSettle();
        expect(find.text('Target request / 1件'), findsNothing);
        expect(find.text('Other request / 1件'), findsOneWidget);
        expect(find.textContaining('old detail failure'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('閉じる'));
        await tester.pumpAndSettle();
      },
    );
  }
}

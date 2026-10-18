import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_open_session.dart';
import 'package:sk_works/features/notifications/notification_explanation_page.dart';
import 'package:sk_works/features/notifications/attention_center_item.dart';

AttentionCenterItem item(String? key) => AttentionCenterItem(
  id: 'notice',
  state: AttentionCenterState.information,
  source: 'notification',
  title: 'Saved notice title',
  body: 'Saved notice body',
  actionKey: key,
);
void main() {

  testWidgets('background blocks a delayed related-screen operation', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final events = StreamController<String?>.broadcast(sync: true);
    final session = NotificationOpenSession(actor: () => 'actor', changes: events.stream);
    final response = Completer<void>();
    var writes = 0;
    await tester.pumpWidget(MaterialApp(home: NotificationExplanationPage(
      item: item('invoice_approval'), isCurrent: () => session.isCurrent,
      invalidations: session.invalidations, onInvalidate: session.invalidate,
      openTarget: (_) async { await response.future; session.requireCurrent(); writes++; },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開く')); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    response.complete(); await tester.pumpAndSettle();
    expect(session.isCurrent, isFalse); expect(writes, 0);
    expect(find.text('Saved notice body'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async { await session.dispose(); await events.close(); });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('ordinary notice acknowledges only after its body is rendered', (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: NotificationExplanationPage(
      item: item(null), onShown: () async { reads++; }, openTarget: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Saved notice body'), findsOneWidget); expect(reads, 1);
  });

  test(
    'account switch is sticky including ABA; snapshot cannot be reused',
    () async {
      var actor = 'actor-a';
      final changes = StreamController<String?>.broadcast(sync: true);
      final session = NotificationOpenSession(
        actor: () => actor,
        changes: changes.stream,
      );
      expect(session.isCurrent, isTrue);
      actor = 'actor-b';
      changes.add(actor);
      actor = 'actor-a';
      changes.add(actor);
      expect(session.isCurrent, isFalse);
      expect(session.requireCurrent, throwsStateError);
      await session.dispose();
      await changes.close();
    },
  );
  for (final key in <String?>[
    null,
    '',
    'future_notification',
    'invoice_approval',
  ]) {
    testWidgets('notice body opens even without a usable target: $key', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationExplanationPage(
            item: item(key),
            canOpenTarget: () async => false,
            openTarget: (_) async {
              calls++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved notice title'), findsOneWidget);
      expect(find.text('Saved notice body'), findsOneWidget);
      expect(find.text('開く'), findsNothing);
      expect(calls, 0);
    });
  }
  testWidgets('revocation clears body and ignores late availability', (
    tester,
  ) async {
    final changes = StreamController<void>.broadcast(sync: true);
    final available = Completer<bool>();
    var current = true;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationExplanationPage(
          item: item('invoice_approval'),
          isCurrent: () => current,
          invalidations: changes.stream,
          canOpenTarget: () => available.future,
          openTarget: (_) async {
            calls++;
          },
        ),
      ),
    );
    expect(find.text('Saved notice body'), findsOneWidget);
    current = false;
    changes.add(null);
    await tester.pump();
    available.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Saved notice body'), findsNothing);
    expect(find.text('通知一覧を開き直してください。'), findsOneWidget);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(changes.close);
  });
  testWidgets('background removes notice body until route is reopened', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationExplanationPage(
          item: item(null),
          openTarget: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('Saved notice body'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Saved notice body'), findsNothing);
  });
}

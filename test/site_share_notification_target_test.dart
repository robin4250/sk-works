import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_share_approval_page.dart';

const target = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const unavailable = '対象の現場共有は完了済み、または閲覧できません。';
typedef Rows = List<Map<String, dynamic>>;
typedef Respond =
    Future<String?> Function({
      required String dataItemId,
      required bool accept,
    });

Map<String, dynamic> row(String id, String name) => {
  'data_item_id': id,
  'status': 'pending',
  'sender_company_name': 'Saved sender',
  'payload': {'name': name},
};

Future<void> show(
  WidgetTester tester,
  String? id,
  Future<Rows> Function() load, {
  Respond? respond,
}) => tester.pumpWidget(
  MaterialApp(
    home: SiteShareApprovalPage(
      initialRequestId: id,
      loadInbox: load,
      respond: respond,
    ),
  ),
);

Finder get cardAccept => find.widgetWithText(FilledButton, '承認して追加');
Finder get dialogAccept => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.text('承認して追加'),
);

void main() {
  testWidgets('ordinary inbox retains existing authorized order', (
    tester,
  ) async {
    await show(
      tester,
      null,
      () async => [row(other, 'First'), row(target, 'Second')],
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('First')).dy,
      lessThan(tester.getTopLeft(find.text('Second')).dy),
    );
    expect(cardAccept, findsNWidgets(2));
  });

  testWidgets(
    'notification shows exact data item rather than payload site ID',
    (tester) async {
      await show(
        tester,
        target,
        () async => [
          row(other, 'Other')..['payload'] = {'name': 'Other', 'id': target},
          row(target, 'Target'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Target'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
    },
  );

  for (final id in [target, '', 'invalid', '$target ']) {
    testWidgets('missing or invalid target $id never opens another share', (
      tester,
    ) async {
      await show(tester, id, () async => [row(other, 'Other')]);
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsNothing);
      expect(find.text(unavailable), findsOneWidget);
      expect(cardAccept, findsNothing);
    });
  }

  for (final fail in [false, true]) {
    testWidgets('target switch rejects delayed old result error=$fail', (
      tester,
    ) async {
      final old = Completer<Rows>();
      var reads = 0;
      Future<Rows> load() =>
          reads++ == 0 ? old.future : Future.value([row(other, 'Current')]);
      await show(tester, target, load);
      final state = tester.state(find.byType(SiteShareApprovalPage));
      await show(tester, other, load);
      expect(tester.state(find.byType(SiteShareApprovalPage)), same(state));
      await tester.pumpAndSettle();
      if (fail) {
        old.completeError(StateError('stale failure'));
      } else {
        old.complete([row(target, 'Old')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Old'), findsNothing);
      expect(find.textContaining('stale failure'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposed read ignores late result error=$fail', (
      tester,
    ) async {
      final old = Completer<Rows>();
      await show(tester, target, () => old.future);
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        old.completeError(StateError('disposed failure'));
      } else {
        old.complete([row(target, 'Old')]);
      }
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switch clears a visible row before next read completes', (
    tester,
  ) async {
    final next = Completer<Rows>();
    var reads = 0;
    Future<Rows> load() =>
        reads++ == 0 ? Future.value([row(target, 'Old')]) : next.future;
    await show(tester, target, load);
    await tester.pumpAndSettle();
    await show(tester, other, load);
    expect(find.text('Old'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    next.complete([]);
    await tester.pumpAndSettle();
    expect(find.text(unavailable), findsOneWidget);
  });

  testWidgets('confirmation for old target cannot send after target switch', (
    tester,
  ) async {
    var writes = 0;
    Future<String?> respond({
      required String dataItemId,
      required bool accept,
    }) async {
      writes++;
      return null;
    }

    Future<Rows> load() async => [row(target, 'Old'), row(other, 'Current')];
    await show(tester, target, load, respond: respond);
    await tester.pumpAndSettle();
    await tester.tap(cardAccept);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await show(tester, other, load, respond: respond);
    await tester.pumpAndSettle();
    await tester.tap(dialogAccept);
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('現場データを追加しました'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation after page disposal sends nothing', (tester) async {
    var writes = 0;
    final body = ValueNotifier<Widget>(
      SiteShareApprovalPage(
        initialRequestId: target,
        loadInbox: () async => [row(target, 'Target')],
        respond: ({required String dataItemId, required bool accept}) async {
          writes++;
          return null;
        },
      ),
    );
    addTearDown(body.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<Widget>(
          valueListenable: body,
          builder: (_, child, __) => child,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(cardAccept);
    await tester.pumpAndSettle();
    body.value = const SizedBox();
    await tester.pumpAndSettle();
    expect(find.byType(SiteShareApprovalPage), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(dialogAccept);
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'response failure releases buttons without automatically resending',
    (tester) async {
      var writes = 0;
      var reads = 0;
      await show(
        tester,
        target,
        () async {
          reads++;
          return [row(target, 'Target')];
        },
        respond: ({required String dataItemId, required bool accept}) async {
          writes++;
          throw StateError('fixture response unavailable');
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(cardAccept);
      await tester.pumpAndSettle();
      await tester.tap(dialogAccept);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(reads, 1);
      expect(
        find.textContaining('fixture response unavailable'),
        findsOneWidget,
      );
      expect(find.text('現場データを追加しました'), findsNothing);
      expect(tester.widget<FilledButton>(cardAccept).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 10));
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets('in-flight response cannot replace new target error=$fail', (
      tester,
    ) async {
      final response = Completer<String?>();
      var writes = 0;
      var reads = 0;
      Future<Rows> load() async {
        reads++;
        return [row(target, 'Old'), row(other, 'Current')];
      }

      Future<String?> respond({
        required String dataItemId,
        required bool accept,
      }) {
        expectSync(dataItemId, target);
        expectSync(accept, true);
        writes++;
        return response.future;
      }

      await show(tester, target, load, respond: respond);
      await tester.pumpAndSettle();
      // Invoke the stale callback twice before rebuilding to exercise the guard.
      final callback = tester.widget<FilledButton>(cardAccept).onPressed!;
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(dialogAccept);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(tester.widget<FilledButton>(cardAccept).onPressed, isNull);
      await show(tester, other, load, respond: respond);
      await tester.pumpAndSettle();
      if (fail) {
        response.completeError(StateError('old response failure'));
      } else {
        response.complete('saved-site-id');
      }
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(writes, 1);
      expect(find.text('Current'), findsOneWidget);
      expect(find.textContaining('old response failure'), findsNothing);
      expect(find.text('現場データを追加しました'), findsNothing);
      expect(tester.widget<FilledButton>(cardAccept).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final accept in [false, true]) {
    testWidgets(
      'current confirmation sends exact target accept=$accept and reloads',
      (tester) async {
        var writes = 0;
        var reads = 0;
        Future<Rows> load() async =>
            reads++ == 0 ? [row(target, 'Target')] : [];
        final expectedDecision = accept;
        Future<String?> respond({
          required String dataItemId,
          required bool accept,
        }) async {
          expect(dataItemId, target);
          expect(accept, expectedDecision);
          writes++;
          return null;
        }

        await show(tester, target, load, respond: respond);
        await tester.pumpAndSettle();
        await tester.tap(
          accept ? cardAccept : find.widgetWithText(OutlinedButton, '拒否'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          accept
              ? dialogAccept
              : find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.text('拒否する'),
                ),
        );
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(reads, 2);
        expect(
          find.text(accept ? '現場データを追加しました' : '現場データを拒否しました'),
          findsOneWidget,
        );
        expect(find.text(unavailable), findsOneWidget);
      },
    );
  }
}

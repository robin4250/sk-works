import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_page.dart';

void main() {
  Future<void> open(WidgetTester tester,
      Future<SiteRecord> Function(SiteRecord) save,
      void Function(SiteRecord?) returned) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(body: TextButton(
        onPressed: () async {
          returned(await Navigator.of(context).push<SiteRecord>(
            MaterialPageRoute(builder: (_) => SiteFormPage(onSave: save)),
          ));
        },
        child: const Text('open'),
      ));
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '墨田現場');
    await tester.enterText(find.byType(TextFormField).at(1), '取引会社');
    await tester.scrollUntilVisible(find.text('登録する'), 350,
        scrollable: find.byType(Scrollable).last);
  }

  testWidgets('waits for save, blocks duplicate submit and back, returns saved row',
      (tester) async {
    final pending = Completer<SiteRecord>();
    var calls = 0;
    SiteRecord? result;
    await open(tester, (draft) { calls++; return pending.future; },
        (value) => result = value);
    await tester.tap(find.text('登録する'));
    await tester.pump();
    expect(calls, 1);
    expect(result, isNull);
    expect(find.text('保存中…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(SiteFormPage), findsOneWidget);
    pending.complete(const SiteRecord(id: 'saved-id', name: '墨田現場',
        customerName: '取引会社', status: SiteStatus.preparing));
    await tester.pumpAndSettle();
    expect(result?.id, 'saved-id');
    expect(find.byType(SiteFormPage), findsNothing);
  });

  testWidgets('failure retains all input and permits deliberate retry',
      (tester) async {
    var calls = 0;
    SiteRecord? result;
    await open(tester, (draft) async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return draft;
    }, (value) => result = value);
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('site-save-error')), findsOneWidget);
    expect(result, isNull);
    expect(find.byType(SiteFormPage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('現場名'), -350,
        scrollable: find.byType(Scrollable).last);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(0))
        .controller?.text, '墨田現場');
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1))
        .controller?.text, '取引会社');
    await tester.scrollUntilVisible(find.text('登録する'), 350,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('登録する'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result?.name, '墨田現場');
  });
}

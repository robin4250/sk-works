import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_cloud_repository.dart';
import 'package:sk_works/features/sites/site_detail_page.dart';
import 'package:sk_works/features/sites/site_page.dart';

void main() {
  Finder scrollable() => find.descendant(
      of: find.byType(ListView), matching: find.byType(Scrollable)).first;

  Future<void> open(WidgetTester tester,
      Future<void> Function(Map<String, String>) submit,
      void Function(bool?) returned) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(body: TextButton(
        onPressed: () async {
          returned(await Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => SiteEditRequestPage(
              site: const SiteRecord(id: 'site-1', name: '元の現場',
                customerId: 'customer-1', customerName: '取引会社',
                status: SiteStatus.active),
              onSubmit: submit,
              loadTradeCompanies: () async => const [
                SiteTradeCompanyOption(tradeCompanyId: 'trade-1',
                    customerId: 'customer-1', name: '取引会社')],
              loadManagers: () async => const [],
            ),
          )));
        },
        child: const Text('open'),
      ));
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '現場名'), '更新した現場');
    await tester.scrollUntilVisible(find.text('変更内容を確認'), 350,
        scrollable: scrollable());
  }

  Future<void> checkName(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('現場名'), -350,
        scrollable: scrollable());
    expect(tester.widget<TextField>(find.widgetWithText(TextField, '現場名'))
        .controller?.text, '更新した現場');
    await tester.scrollUntilVisible(find.text('変更内容を確認'), 350,
        scrollable: scrollable());
  }

  testWidgets('cancel confirmation retains edited input without submitting',
      (tester) async {
    var calls = 0;
    bool? result;
    await open(tester, (_) async { calls++; }, (value) => result = value);
    await tester.tap(find.text('変更内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(result, isNull);
    expect(find.byType(SiteEditRequestPage), findsOneWidget);
    await checkName(tester);
  });

  testWidgets('failed request retains input and can explicitly retry',
      (tester) async {
    var calls = 0;
    bool? result;
    await open(tester, (values) async {
      expect(values['customer_id'], 'customer-1');
      expect(values['name'], '更新した現場');
      calls++;
      if (calls == 1) throw StateError('offline');
    }, (value) => result = value);
    await tester.tap(find.text('変更内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定して申請'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('site-edit-submit-error')), findsOneWidget);
    expect(result, isNull);
    await checkName(tester);
    await tester.tap(find.text('変更内容を確認'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定して申請'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result, isTrue);
    expect(find.byType(SiteEditRequestPage), findsNothing);
  });

  testWidgets('busy and successful return block duplicate request callbacks',
      (tester) async {
    var calls = 0;
    var returns = 0;
    bool? result;
    final pending = Completer<void>();
    await open(tester, (_) { calls++; return pending.future; }, (value) {
      result = value;
      returns++;
    });
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final staleSubmit = button.onPressed!;
    await tester.tap(find.text('変更内容を確認'));
    await tester.pumpAndSettle();
    staleSubmit();
    await tester.pump();
    expect(find.text('確定して申請'), findsOneWidget);
    await tester.tap(find.text('確定して申請'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    expect(result, isNull);
    expect(tester.widgetList<TextField>(find.byType(TextField))
        .every((field) => field.enabled == false), isTrue);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(SiteEditRequestPage), findsOneWidget);
    staleSubmit();
    expect(calls, 1);
    pending.complete();
    await tester.pump();
    staleSubmit();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(returns, 1);
    expect(result, isTrue);
  });
}

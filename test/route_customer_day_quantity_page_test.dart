import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/branding/sko_theme.dart';
import 'package:sk_works/features/route_billing/route_customer_day_quantity_page.dart';
import 'package:sk_works/features/route_billing/route_customer_day_quantity_repository.dart';

class _Access implements RouteCustomerQuantityAccess {
  bool changed = false;
  int sends = 0;
  Map<String, double>? sent;
  final day = const RouteCustomerQuantityDay([
    RouteCustomerQuantityCandidate(id: 'a', name: '株式会社長い名前の取引会社A',
      reportIds: ['a1','a2'], sites: ['現場1','現場2'], version: 0),
    RouteCustomerQuantityCandidate(id: 'b', name: '取引会社B',
      reportIds: ['b1'], sites: ['現場3'], version: 0),
  ], 0);
  @override
  String get actor => 'actor';
  @override
  void checkActor(String captured) {
    if (changed || captured != actor) throw StateError('account changed');
  }
  @override
  Future<RouteCustomerQuantityDay> load(String workerId, DateTime date) async => day;
  @override
  Future<void> submit(String workerId, DateTime date, RouteCustomerQuantityDay day,
    Map<String, double> quantities) async {
    checkActor(actor); sends++; sent = quantities;
  }
}

void main() {
  Future<_Access> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320,720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final access = _Access();
    await tester.pumpWidget(MaterialApp(theme: SkoTheme.light(SkoTheme.palettes.first),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.3)), child: child!),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
          RouteCustomerDayQuantityPage(workerId: 'worker', workDate: DateTime(2026,10,12), accessOverride: access))),
        child: const Text('開く'))))));
    await tester.tap(find.text('開く'));await tester.pumpAndSettle();return access;
  }
  Future<void> choose(WidgetTester tester) async {
    final buttons = find.byType(SegmentedButton<double>);
    for (var i=0;i<2;i++) {
      await tester.ensureVisible(buttons.at(i));
      await tester.tap(find.descendant(of: buttons.at(i), matching: find.text('1人工')));
      await tester.pumpAndSettle();
    }
  }
  testWidgets('explicit company quantities may total two and are sent only by the submit button at 320px', (tester) async {
    final access = await pump(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'申請')).onPressed,isNull);
    expect(access.sends,0);
    await choose(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'申請')).onPressed,isNotNull);
    await tester.tap(find.text('申請'));await tester.pumpAndSettle();
    expect(access.sent,{'a':1.0,'b':1.0});expect(access.sends,1);
    expect(tester.takeException(),isNull);
  });
  testWidgets('back does not send selected quantities', (tester) async {
    final access = await pump(tester);await choose(tester);
    await tester.pageBack();await tester.pumpAndSettle();
    expect(access.sends,0);expect(find.text('開く'),findsOneWidget);
  });
  testWidgets('changed actor cannot submit cached quantities', (tester) async {
    final access = await pump(tester);await choose(tester);access.changed = true;
    await tester.tap(find.text('申請'));await tester.pumpAndSettle();
    expect(access.sends,0);
    expect(find.text('申請できませんでした。申請や日報が更新された場合は再読み込みしてください。'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'申請')).onPressed,isNull);
  });
}

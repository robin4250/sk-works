import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/route_billing/route_customer_day_quantity_page.dart';
import 'package:sk_works/features/route_billing/route_customer_day_quantity_repository.dart';

class _EvidenceAccess implements RouteCustomerQuantityAccess {
  _EvidenceAccess(this.day);
  final RouteCustomerQuantityDay day;
  int sends = 0;
  @override
  String get actor => 'actor';
  @override
  void checkActor(String captured) {
    if (captured != actor) throw StateError('actor changed');
  }
  @override
  Future<RouteCustomerQuantityDay> load(String workerId, DateTime date) async => day;
  @override
  Future<void> submit(String workerId, DateTime date, RouteCustomerQuantityDay day,
    Map<String, double> quantities) async { sends++; }
}

void main() {
  test('diagnostic counts reject missing, negative, fractional and inconsistent evidence', () {
    final valid = <String,Object>{
      'completed_report_count': 5, 'eligible_report_count': 2,
      'unresolved_customer_count': 0, 'missing_source_count': 3,
      'waiting_checkout_count': 0,
    };
    expect(RouteQuantityEvidenceDiagnostics.fromJson(valid).missingSourceCount,3);
    for (final value in [
      <String,Object>{}, {...valid,'missing_source_count':-1},
      {...valid,'eligible_report_count':2.5}, {...valid,'completed_report_count':6},
    ]) {
      expect(() => RouteQuantityEvidenceDiagnostics.fromJson(value),throwsStateError);
    }
  });

  Future<void> open(WidgetTester tester, _EvidenceAccess access) async {
    tester.view.physicalSize = const Size(320,720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder:(context,child)=>MediaQuery(
        data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.3)),
        child:child!),
      home:RouteCustomerDayQuantityPage(workerId:'worker',
        workDate:DateTime(2026,10,12),accessOverride:access)));
    await tester.pumpAndSettle();
  }

  testWidgets('saved reports with missing source are explained and never become fabricated quantities', (tester) async {
    final access = _EvidenceAccess(const RouteCustomerQuantityDay([],0,
      diagnostics:RouteQuantityEvidenceDiagnostics(
        completedReportCount:3,eligibleReportCount:0,unresolvedCustomerCount:0,
        missingSourceCount:3,waitingCheckoutCount:0)));
    await open(tester,access);
    expect(find.textContaining('元の出勤・退勤記録を確認できない日報：3件'),findsOneWidget);
    expect(find.textContaining('署名まで完了した訪問日報が見つかりません'),findsNothing);
    expect(find.textContaining('取引会社が未設定の現場があります'),findsNothing);
    expect(find.byType(SegmentedButton<double>),findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'申請')).onPressed,isNull);
    expect(access.sends,0);expect(tester.takeException(),isNull);
  });

  testWidgets('older missing records do not disable a valid displayed candidate', (tester) async {
    final access = _EvidenceAccess(const RouteCustomerQuantityDay([
      RouteCustomerQuantityCandidate(id:'customer',name:'取引会社',reportIds:['report'],
        sites:['現場'],version:0),
    ],0,diagnostics:RouteQuantityEvidenceDiagnostics(
      completedReportCount:2,eligibleReportCount:1,unresolvedCustomerCount:0,
      missingSourceCount:1,waitingCheckoutCount:0)));
    await open(tester,access);
    final buttons = find.byType(SegmentedButton<double>);
    await tester.ensureVisible(buttons);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:buttons,matching:find.text('1人工')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'申請')).onPressed,isNotNull);
    expect(access.sends,0);expect(tester.takeException(),isNull);
  });

  testWidgets('unavailable diagnostics are not rendered as zero or no reports', (tester) async {
    await open(tester,_EvidenceAccess(const RouteCustomerQuantityDay([],0)));
    expect(find.textContaining('根拠確認情報は未取得'),findsOneWidget);
    expect(find.textContaining('自分が作成した対象日の完了訪問日報：0件'),findsNothing);
    expect(find.textContaining('署名まで完了した訪問日報が見つかりません'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}

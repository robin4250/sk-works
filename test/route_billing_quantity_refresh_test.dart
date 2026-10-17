import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/route_billing/route_billing_quantity_approval_repository.dart';
import 'package:sk_works/features/route_billing/route_billing_quantity_approvals_page.dart';

class _Rows extends Fake implements RouteBillingQuantityApprovalRepository {
  int reads = 0;
  Completer<List<RouteBillingQuantityRequest>>? next;
  Completer<RouteBillingQuantityRequest>? opened;
  bool fail = false;
  List<RouteBillingQuantityRequest> rows = [];
  final item = RouteBillingQuantityRequest({
    'id': 'request-a', 'customer_name': '取引会社A', 'worker_name': '担当者',
    'work_date': '2026-10-17', 'quantity': 1, 'status': 'pending',
    'version': 3, 'evidence': <Object>[], 'site_options': <Object>[],
  });
  @override
  Future<List<RouteBillingQuantityRequest>> pending() async {
    reads++;
    if (next != null) return next!.future;
    if (fail) throw StateError('読み込み失敗');
    return rows;
  }
  @override
  Future<RouteBillingQuantityRequest> detail(String id) async =>
      opened == null ? item : opened!.future;
}

Future<void> _show(WidgetTester tester, _Rows rows) async {
  await tester.pumpWidget(MaterialApp(
    home: RouteBillingQuantityApprovalsPage.forTesting(repositoryOverride: rows),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty approval list can refresh after new application arrives', (tester) async {
    final rows = _Rows();
    await _show(tester, rows);
    expect(find.text('承認待ちはありません'), findsOneWidget);
    rows.rows = [rows.item];
    await tester.tap(find.byTooltip('再読み込み'));
    await tester.pumpAndSettle();
    expect(rows.reads, 2);
    expect(find.text('取引会社A'), findsOneWidget);
    expect(find.text('承認待ちはありません'), findsNothing);
  });
  testWidgets('empty list pull gesture performs the same safe reload', (tester) async {
    final rows = _Rows();
    await _show(tester, rows);
    rows.rows = [rows.item];
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(rows.reads, 2);
    expect(find.text('取引会社A'), findsOneWidget);
  });
  testWidgets('rapid reloads are coalesced and disabled until the read completes', (tester) async {
    final rows = _Rows();
    await _show(tester, rows);
    rows.next = Completer<List<RouteBillingQuantityRequest>>();
    final indicator = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final a = indicator.onRefresh();
    final b = indicator.onRefresh();
    await tester.pump();
    expect(rows.reads, 2);
    final button = tester.widget<IconButton>(find.byTooltip('再読み込み'));
    expect(button.onPressed, isNull);
    rows.next!.complete([rows.item]);
    await Future.wait([a,b]);
    await tester.pumpAndSettle();
    expect(find.text('取引会社A'), findsOneWidget);
  });
  testWidgets('opening a decision prevents both toolbar and gesture reload', (tester) async {
    final rows = _Rows();
    rows.rows = [rows.item];
    rows.opened = Completer<RouteBillingQuantityRequest>();
    await _show(tester, rows);
    await tester.tap(find.text('取引会社A'));
    await tester.pump();
    expect(tester.widget<IconButton>(find.byTooltip('再読み込み')).onPressed, isNull);
    await tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    expect(rows.reads, 1);
    rows.opened!.complete(rows.item);
    await tester.pumpAndSettle();
    expect(find.text('請求数量'), findsOneWidget);
  });
  testWidgets('failed reload stays an error and retry recovers without inventing empty success', (tester) async {
    final rows = _Rows();
    await _show(tester, rows);
    rows.fail = true;
    await tester.tap(find.byTooltip('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.textContaining('読み込み失敗'), findsOneWidget);
    expect(find.text('承認待ちはありません'), findsNothing);
    rows.fail = false;
    rows.rows = [rows.item];
    await tester.tap(find.widgetWithText(TextButton, '再読み込み'));
    await tester.pumpAndSettle();
    expect(rows.reads, 3);
    expect(find.text('取引会社A'), findsOneWidget);
  });
}

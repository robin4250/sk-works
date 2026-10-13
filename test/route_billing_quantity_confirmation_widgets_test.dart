import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/route_billing/route_billing_quantity_approval_repository.dart';
import 'package:sk_works/features/route_billing/route_billing_quantity_approvals_page.dart';

class _Repository extends Fake
    implements RouteBillingQuantityApprovalRepository {
  final calls = <Map<String, Object?>>[];
  final request = RouteBillingQuantityRequest({
    'id': 'request-a',
    'customer_name': '取引会社A',
    'worker_name': '担当者',
    'work_date': '2026-10-11',
    'quantity': 1,
    'status': 'pending',
    'version': 3,
    'evidence': [
      {'site_id': 'site-a', 'site_name': '現場A'},
    ],
    'site_options': [
      {
        'site_id': 'site-a',
        'site_name': '現場A',
        'unit_price_yen': 25000,
        'man_day_method': true,
      },
    ],
  });
  @override
  Future<List<RouteBillingQuantityRequest>> pending() async =>
      calls.isEmpty ? [request] : [];
  @override
  Future<RouteBillingQuantityRequest> detail(String id) async => request;
  @override
  Future<String> decide({
    required RouteBillingQuantityRequest request,
    required bool approve,
    required double quantity,
    String? siteId,
    int? unitPriceYen,
    String? note,
  }) async {
    calls.add({
      'id': request.id,
      'version': request.version,
      'quantity': quantity,
      'site': siteId,
      'price': unitPriceYen,
    });
    return approve ? 'approved' : 'rejected';
  }
}

void main() {
  testWidgets(
    'approval confirms explicit customer, evidenced site, quantity and registered price; cancel never sends',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: RouteBillingQuantityApprovalsPage.forTesting(
            repositoryOverride: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取引会社A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.5人工'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('現場A').last);
      await tester.pumpAndSettle();
      expect(find.text('25000'), findsOneWidget);
      await tester.ensureVisible(find.text('承認'));
      await tester.tap(find.text('承認'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('請求現場：現場A'), findsOneWidget);
      expect(find.textContaining('請求額：12500円'), findsOneWidget);
      expect(repository.calls, isEmpty);
      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      await tester.tap(find.text('承認'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('承認する'));
      await tester.pumpAndSettle();
      expect(repository.calls.single, {
        'id': 'request-a',
        'version': 3,
        'quantity': 0.5,
        'site': 'site-a',
        'price': 25000,
      });
      expect(find.text('承認待ちはありません'), findsOneWidget);
    },
  );
}

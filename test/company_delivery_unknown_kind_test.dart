import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sk_works/features/people/company_delivery_inbox_page.dart';
import 'package:sk_works/features/people/company_document_exchange_repository.dart';

class _Repository implements CompanyDocumentExchangeRepository {
  int saves = 0;
  @override
  Future<List<Map<String, dynamic>>> listDeliveries() async => [
    {'id': 'delivery', 'received': true, 'sender_name': '取引会社'},
  ];
  @override
  Future<List<Map<String, dynamic>>> listTransferTargets() async => [];
  @override
  Future<Map<String, dynamic>> loadConnectionInbox() async => {};
  @override
  Future<Map<String, DateTime>> loadSavedDeliveryState() async => {};
  @override
  Future<List<Map<String, dynamic>>> listDeliveryItems(String id) async => [];
  @override
  Future<List<Map<String, dynamic>>> listDeliveryDataItems(String id) async => [
    {
      'id': 'old',
      'payload_kind': 'personnel',
      'payload': {'name': '従業員'},
    },
    {
      'id': 'qualification',
      'payload_kind': 'qualification',
      'payload': {'worker_name': '従業員', 'qualification_name': '資格名'},
    },
    {
      'id': 'new',
      'payload_kind': 'site_share',
      'payload': {'name': '専用現場'},
    },
    {
      'id': 'signature',
      'payload_kind': 'signature',
      'payload': {'signer_name': '非表示署名者'},
    },
    {
      'id': 'detail',
      'payload_kind': 'personnel_detail',
      'payload': {'name': '非表示社員詳細'},
    },
  ];
  @override
  Future<void> saveDeliveryItems(Iterable<String> keys) async {
    saves++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'unknown kind is visible as unavailable and cannot be selected or saved',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        MaterialApp(
          home: CompanyDeliveryInboxPage.forTesting(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取引会社').first);
      await tester.pumpAndSettle();
      final boxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(boxes, hasLength(5));
      expect(boxes.where((tile) => tile.onChanged != null), hasLength(2));
      expect(find.text('従業員'), findsOneWidget);
      expect(find.text('従業員 / 資格名'), findsOneWidget);
      expect(find.text('この画面では操作できない受信データ'), findsNWidgets(3));
      expect(find.text('専用現場'), findsNothing);
      expect(find.textContaining('非表示署名者'), findsNothing);
      expect(find.text('非表示社員詳細'), findsNothing);
      await tester.tap(find.byTooltip('会社単位で一括保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('専用の承認画面で確認してください。'), findsOneWidget);
      expect(repository.saves, 0);
    },
  );
}

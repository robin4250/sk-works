import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';

class _Gateway implements OwnDocumentRegistrationGateway {
  int saved = 0;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
    'workers': [{'id': 'worker', 'name': '本人'}],
    'requirements': [{'id': 'license', 'name': '運転免許証', 'scope': 'internal', 'is_active': true}],
    'statuses': [],
  };
  @override
  Future<void> saveOwnDocument({required String requirementId, DateTime? expiresAt,
    required String notes, Uint8List? attachmentBytes, String? originalFilename,
    bool requireEmptyAttachment = false}) async { saved++; }
}

void main() {
  testWidgets('書類登録は番号順に必須と任意を案内して登録できる', (tester) async {
    final gateway = _Gateway();
    await tester.pumpWidget(MaterialApp(home: OwnDocumentRegistrationPage(gateway: gateway)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '書類を登録'));
    await tester.pumpAndSettle();
    expect(find.text('①'), findsOneWidget);
    expect(find.text('②'), findsOneWidget);
    expect(find.text('③'), findsOneWidget);
    expect(find.text('④'), findsOneWidget);
    expect(find.text('⑤ '), findsOneWidget);
    expect(find.text('選択済み'), findsOneWidget);
    expect(find.text('任意'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '登録'));
    await tester.pumpAndSettle();
    expect(gateway.saved, 1);
  });
}

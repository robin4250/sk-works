import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';

class Documents implements OwnDocumentRegistrationGateway {
  int ordinarySaves = 0;
  @override
  Future<Map<String,List<Map<String,dynamic>>>> loadAll() async => {
    'workers':[{'id':'40000000-0000-0000-0000-000000000001','name':'本人'}],
    'requirements':[{'id':'50000000-0000-0000-0000-000000000001','company_id':'30000000-0000-0000-0000-000000000001','name':'銀行口座情報','is_active':true,'is_required':true,'scope':'internal'}],
    'statuses':[],
  };
  @override
  Future<void> saveOwnDocument({required String requirementId, DateTime? expiresAt,
    required String notes, Uint8List? attachmentBytes, String? originalFilename,
    bool requireEmptyAttachment=false}) async { ordinarySaves++; }
}
void main() {
  testWidgets('bank requirement opens bank fields rather than ordinary photo document registration', (t) async {
    final docs=Documents();
    await t.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:docs)));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton,'登録').first); await t.pumpAndSettle();
    expect(find.text('銀行口座情報を登録'),findsOneWidget);
    expect(find.text('写真を添付する'),findsNothing);
    expect(docs.ordinarySaves,0);
    await t.pumpWidget(const SizedBox());
  });
}

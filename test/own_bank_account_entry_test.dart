import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';

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
class BankMetadata extends ChangeNotifier implements OwnBankAccountGateway {
  BankMetadata({this.registered=false,this.denied=false});
  final bool registered,denied;
  @override bool get isCurrent=>true;
  @override Future<OwnBankAccountState> load() async {
    if(denied) throw StateError('Synthetic metadata denied');
    return OwnBankAccountState(registered:registered);
  }
  @override Future<OwnBankAccountState> register(OwnBankAccountInput input) async => throw StateError('Unexpected fixture write');
  @override Future<void> close() async {dispose();}
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
  testWidgets('bank card with unregistered metadata opens dedicated input fields', (t) async {
    final docs=Documents(),bank=BankMetadata();
    await t.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:docs,bankGateway:bank)));
    await t.pumpAndSettle();await t.tap(find.widgetWithText(FilledButton,'登録').first);await t.pumpAndSettle();
    expect(find.byKey(const Key('bank-name')),findsOneWidget);expect(find.byKey(const Key('bank-number')),findsOneWidget);
    expect(find.text('写真を添付する'),findsNothing);expect(docs.ordinarySaves,0);
    await t.pumpWidget(const SizedBox());await bank.close();
  });
  testWidgets('saved private bank metadata makes card registered without requiring a photo/status stub', (t) async {
    final docs=Documents(),bank=BankMetadata(registered:true);
    await t.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:docs,bankGateway:bank)));
    await t.pumpAndSettle();expect(find.text('登録済み'),findsOneWidget);
    await t.tap(find.widgetWithText(OutlinedButton,'確認・編集'));await t.pumpAndSettle();
    expect(find.text('銀行口座情報は登録済みです。'),findsOneWidget);expect(find.byType(TextFormField),findsNothing);
    expect(docs.ordinarySaves,0);await t.pumpWidget(const SizedBox());await bank.close();
  });
  testWidgets('denied bank metadata never claims registered or enables blind insert', (t) async {
    final docs=Documents(),bank=BankMetadata(denied:true);
    await t.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:docs,bankGateway:bank)));
    await t.pumpAndSettle();expect(find.text('登録済み'),findsNothing);expect(find.text('口座情報を確認'),findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton,'登録').first);await t.pumpAndSettle();
    expect(find.byType(TextFormField),findsNothing);expect(docs.ordinarySaves,0);
    await t.pumpWidget(const SizedBox());await bank.close();
  });

}

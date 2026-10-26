import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';

class FakeGateway implements OwnDocumentRegistrationGateway {
  FakeGateway(this.requirement, this.status);
  final Map<String, dynamic> requirement;
  final Map<String, dynamic>? status;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
    'workers': [{'id': 'worker', 'name': '本人'}],
    'requirements': [requirement],
    'statuses': [if (status != null) status!],
  };
  @override
  Future<void> saveOwnDocument({required String requirementId,
    DateTime? expiresAt, required String notes,
    Uint8List? attachmentBytes, String? originalFilename,
    bool requireEmptyAttachment = false}) async {}
}

void main() {
  Future<void> show(WidgetTester tester, Map<String,dynamic> req,
      Map<String,dynamic>? status) async {
    await tester.pumpWidget(MaterialApp(home: OwnDocumentRegistrationPage(
      key: UniqueKey(), gateway: FakeGateway(req, status))));
    await tester.pumpAndSettle();
  }
  Map<String,dynamic> req(String name, {bool required = true}) =>
    {'id':'r','name':name,'is_active':true,'is_required':required,'scope':'internal'};
  testWidgets('必須書類の提出後に添付が無ければ添付待ち', (tester) async {
    await show(tester, req('免許証'), {'requirement_id':'r','status':'submitted'});
    expect(find.text('添付待ち'), findsOneWidget);
    expect(find.text('登録済み'), findsNothing);
    await tester.tap(find.byTooltip('詳細を確認'));
    await tester.pump();
    expect(find.text('登録済み書類への添付追加は準備中です。'), findsOneWidget);
  });
  testWidgets('添付があれば登録済み、任意書類は添付を強制しない', (tester) async {
    await show(tester, req('免許証'), {'requirement_id':'r','status':'submitted','attachment_path':'private/object'});
    expect(find.text('登録済み'), findsOneWidget);
    await show(tester, req('任意書類', required:false), {'requirement_id':'r','status':'submitted'});
    expect(find.text('添付待ち'), findsNothing);
  });
  testWidgets('期限切れと口座は誤って完了扱いにしない', (tester) async {
    await show(tester, req('免許証'), {'requirement_id':'r','status':'expired','attachment_path':'private/object'});
    expect(find.text('期限切れ'), findsOneWidget);
    await show(tester, req('銀行口座情報'), {'requirement_id':'r','status':'submitted'});
    expect(find.text('口座情報を確認'), findsOneWidget);
  });
}

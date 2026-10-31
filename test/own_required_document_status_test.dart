import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/own_document_registration_page.dart';

class FakeGateway implements OwnDocumentRegistrationGateway {
  FakeGateway(this.requirement, this.status, {this.exemptions=const []});
  final List<Map<String,dynamic>> exemptions;
  int saves=0;
  final Map<String, dynamic> requirement;
  final Map<String, dynamic>? status;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {
    'workers': [{'id': 'worker', 'name': '本人'}],
    'requirements': [requirement],
    'statuses': [if (status != null) status!],
    'exemptions':exemptions,
  };
  @override
  Future<void> saveOwnDocument({required String requirementId,
    DateTime? expiresAt, required String notes,
    Uint8List? attachmentBytes, String? originalFilename,
    bool requireEmptyAttachment = false}) async {saves++;}
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
    expect(find.text('書類変更申請は準備中です。'), findsOneWidget);
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
  testWidgets('提出免除は未確認の書類状態を併記せず原本を保持する', (tester) async {
    final status=<String,dynamic>{'requirement_id':'r','status':'submitted','attachment_path':'retained/synthetic-original'};
    final gateway=FakeGateway(req('健康診断書'),status,exemptions:[
      {'worker_id':'worker','requirement_id':'r','active':true,'version':1,'reason':'管理者確認'}]);
    await tester.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:gateway)));
    await tester.pumpAndSettle();
    expect(find.text('提出免除'),findsOneWidget);
    expect(find.textContaining('未確認'),findsNothing);
    expect(find.textContaining('提出済み'),findsNothing);
    expect(status['attachment_path'],'retained/synthetic-original');expect(gateway.saves,0);
  });
  testWidgets('期限必須の健康書類は準備完了に期限が必要と示し部分保存は保つ', (tester) async {
    final gateway=FakeGateway({...req('健康診断書'),'expiry_required':true},null);
    await tester.pumpWidget(MaterialApp(home:OwnDocumentRegistrationPage(gateway:gateway)));
    await tester.pumpAndSettle();await tester.tap(find.widgetWithText(FilledButton,'書類を登録'));await tester.pumpAndSettle();
    expect(find.text('有効期限（準備完了に必要）'),findsOneWidget);
    expect(find.text('準備完了に必要'),findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton,'登録').last);await tester.pumpAndSettle();
    expect(gateway.saves,1);
  });

  testWidgets('本人一覧も複数添付と期限未入力を共通判定する', (tester) async {
    await show(tester, req('雇用保険被保険者証'),
      {'requirement_id': 'r', 'status': 'submitted', 'attachment_paths': ['retained/a', 'retained/b']});
    expect(find.text('添付待ち'), findsNothing);
    expect(find.text('登録済み'), findsOneWidget);
    await show(tester, {...req('健康診断書'), 'expiry_required': true},
      {'requirement_id': 'r', 'status': 'submitted', 'attachment_paths': ['retained/a']});
    expect(find.text('登録済み・期限未入力'), findsOneWidget);
    expect(find.text('登録済み'), findsNothing);
  });

  testWidgets('本人一覧も任意の入力済み期限が過去なら完了扱いにしない', (tester) async {
    await show(tester, req('証明書'), {'requirement_id': 'r', 'status': 'submitted',
      'attachment_paths': ['retained/a'], 'expires_at': '2020-01-01'});
    expect(find.text('登録済み・期限切れ'), findsOneWidget);
    expect(find.text('登録済み'), findsNothing);
  });

}

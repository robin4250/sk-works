import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/sites/site_order_company_page.dart';
import 'package:sk_works/features/sites/site_order_history_page.dart';
import 'package:sk_works/features/sites/site_order_send_page.dart';
import 'package:sk_works/features/sites/site_order_workflow.dart';

SiteOrderArtifact order(String title, {String id='order'}) => SiteOrderArtifact(
  id: id, companyId: 'own', siteId: 'site', revision: 1, pdfSha256: 'a'*64, kind: SiteOrderArtifactKind.order,
  title: title, startsOn: '2026-10-01', endsOn: '2026-10-31',
  sealVersionId: 'seal', prices: [
    SiteOrderPrice(item: 'とび工',unitPriceYen:32000,unit:'人日'),
    SiteOrderPrice(item: '運搬',unitPriceYen:2000,unit:'回'),
  ]);
const scope = SiteOrderScope(actorId:'actor',companyId:'own',sessionId:'sid',siteId:'site');
const recipient = SiteOrderRecipient(tradeCompanyId:'trade',companyId:'other',
  name:'協力会社A',connectionVersion:1);

void main() {
  testWidgets('company page gates unfinished archive and retains existing detail action', (tester) async {
    var opened=0;
    await tester.pumpWidget(MaterialApp(home: SiteOrderCompanyPage(
      tradeCompanyId:'registered-company-id',companyName:'協力会社A',
      openCompanyDetails:() async {opened++;})));
    expect(find.text('協力会社A の注文書'),findsOneWidget);
    final receive=tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'受信した注文書・承認待ち'));
    expect(receive.onPressed,isNull);
    await tester.tap(find.text('会社情報・既存の帳票生成を開く'));
    expect(opened,1);
  });

  testWidgets('confirmation shows every canonical price line, recipient and return action', (tester) async {
    final changes=ChangeNotifier(); addTearDown(changes.dispose);
    var sent=0;
    final flow=SiteOrderSendWorkflow(scope:scope,artifact:order('現場A'),currentScope:()=>scope,
      isArtifactCurrent:(_)=>true,isRecipientCurrent:(_)=>true,newRequestId:()=> 'request',
      persistIntent:(_) async {});
    await tester.pumpWidget(MaterialApp(home: SiteOrderSendPage(workflow:flow,
      recipients:const[recipient],scopeChanges:changes,
      lookupReceipt:(_) async=>null,send:(i) async { sent++; throw StateError('unexpected');})));
    await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('協力会社A').last); await tester.pumpAndSettle();
    await tester.tap(find.text('共有送信')); await tester.pumpAndSettle();
    expect(find.text('とび工\n単価 32000円／人日'),findsOneWidget);
    expect(find.text('運搬\n単価 2000円／回'),findsOneWidget);
    expect(find.textContaining('「協力会社A」に共有送信'),findsOneWidget);
    expect(find.text('入力画面に戻る'),findsNWidgets(2));
    expect(sent,0);
  });

  testWidgets('revoked scope closes price confirmation and removes company detail', (tester) async {
    final changes=ChangeNotifier(); addTearDown(changes.dispose);
    var valid=true;
    final flow=SiteOrderSendWorkflow(scope:scope,artifact:order('現場A'),currentScope:()=>scope,
      isArtifactCurrent:(_)=>valid,isRecipientCurrent:(_)=>true,newRequestId:()=> 'request',
      persistIntent:(_) async {});
    await tester.pumpWidget(MaterialApp(home: SiteOrderSendPage(workflow:flow,
      recipients:const[recipient],scopeChanges:changes,
      lookupReceipt:(_) async=>null,send:(_) async=>throw StateError('unexpected'))));
    await tester.tap(find.byType(DropdownButtonFormField<String>)); await tester.pumpAndSettle();
    await tester.tap(find.text('協力会社A').last); await tester.pumpAndSettle();
    await tester.tap(find.text('共有送信')); await tester.pumpAndSettle();
    valid=false; changes.notifyListeners(); await tester.pumpAndSettle();
    expect(find.text('注文書を共有送信しますか？'),findsNothing);
    expect(find.text('とび工\n単価 32000円／人日'),findsNothing);
    expect(find.text('閉じる'),findsOneWidget);
  });

  testWidgets('archive list shows work name and period, clears on permission revocation', (tester) async {
    final changes=ChangeNotifier(); addTearDown(changes.dispose);
    var valid=true;
    await tester.pumpWidget(MaterialApp(home:SiteOrderHistoryPage(orders:[order('現場A')],
      requireScope:(){if(!valid)throw StateError('revoked');},scopeChanges:changes,
      loadPdf:(_) async=>Uint8List(0))));
    expect(find.text('現場A'),findsOneWidget);
    expect(find.text('2026-10-01 ～ 2026-10-31'),findsOneWidget);
    valid=false; changes.notifyListeners(); await tester.pump();
    expect(find.text('現場A'),findsNothing);
    expect(find.text('開き直してください。'),findsOneWidget);
  });

  testWidgets('archive viewer keeps close, swipes work names and rejects wrong PDF hash', (tester) async {
    final changes=ChangeNotifier(); addTearDown(changes.dispose);
    await tester.pumpWidget(MaterialApp(home:SiteOrderArchivePreviewPage(
      orders:[order('現場A'),order('現場B',id:'order-b')],initialIndex:0,
      requireScope:(){},scopeChanges:changes,loadPdf:(_)async=>Uint8List.fromList([1,2,3]))));
    await tester.pumpAndSettle();
    expect(find.text('閉じる'),findsOneWidget);
    expect(find.text('現場A'),findsOneWidget);
    expect(find.text('注文書を表示できません。一覧から開き直してください。'),findsWidgets);
    await tester.drag(find.byType(PageView),const Offset(-700,0)); await tester.pumpAndSettle();
    expect(find.text('現場B'),findsOneWidget);
    expect(find.text('2 / 2件'),findsOneWidget);
    expect(find.text('閉じる'),findsOneWidget);
  });
}

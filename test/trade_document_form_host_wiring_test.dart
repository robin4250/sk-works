import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/shared/trade_document_attachment_editor_page.dart';
import 'package:sk_works/features/shared/trade_document_attachment_repository.dart';
import 'package:sk_works/features/shared/trade_document_form_session.dart';
import 'package:sk_works/features/shared/trade_document_touch_editor_page.dart';

const _actor='10000000-0000-4000-8000-000000000001';
const _company='10000000-0000-4000-8000-000000000002';
const _partner='20000000-0000-4000-8000-000000000001';
const _subject='30000000-0000-4000-8000-000000000001';
const _revision='2026-10-30T00:00:00.000Z';
String _token(String sid){
  String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
  return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':_actor,'session_id':sid,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.${base64Url.encode(List<int>.filled(32,7)).replaceAll('=','')}';
}
Map<String,dynamic> _payload({bool marked=true,bool order=false}){
  var value=<String,dynamic>{'version':1,'kind':order?'order':'acceptance','month':'2026-10','issue_date':'2026-09-30','order_date':'2026-09-30',
    'work_name':'Synthetic saved work','work_address':'Synthetic place','period_start':'2026-10-01','period_end':'2026-10-31',
    'total_amount_yen':110000,'tax_amount_yen':10000,'payment_conditions':'Synthetic agreed payment','notes':'Saved note',
    'acceptance_text':'Synthetic acceptance','issuer':{'name':'Synthetic issuer','address':'Registered issuer address'},
    'counterparty':{'name':'Synthetic counterparty','address':'Registered counterparty address'},
    'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'Synthetic issuer'}};
  if(marked){value=TradeDocumentTermsSnapshot.initialize(value);value=TradeDocumentFormDraft.fromPayload(value,allowAmountEditing:false).payload;}
  return value;
}
Map<String,dynamic> _bank({String partner=_partner,int version=1})=>{
  'schema':1,'company_id':_company,'partner_company_id':partner,'bank_version':version,
  'bank_name':'Synthetic bank','branch_name':'Synthetic branch','account_type':'普通','account_number':'1234567','account_holder':'SYNTHETIC'};
Map<String,dynamic> _workspace({Map<String,dynamic>? saved,Map<String,dynamic>? defaults,bool manage=true,bool changed=false,bool locked=false})=>{
  'company_id':_company,'source_revision':_revision,'can_manage':manage,'source_changed':changed,'source_locked':locked,'source_blocked':false,
  'attachment':{'version':7,'payload':saved??_payload()},'defaults':defaults??_payload(),'template':<String,dynamic>{}};
class _Repo extends TradeDocumentAttachmentRepository{
  _Repo(super.client,TradeDocumentFormSession scope,this.workspace):super(session:scope);
  final Map<String,dynamic> workspace;
  int loads=0,saves=0;int? expected;
  Map<String,dynamic>? sent;
  Completer<TradeDocumentAttachment>? holdSave;
  bool failSave=false;
  @override Future<Map<String,dynamic>> loadWorkspace({required String subjectKind,required String subjectId,required String sourceRevision})async{
    loads++;expect(subjectId,_subject);expect(sourceRevision,_revision);return workspace;
  }
  @override Future<TradeDocumentAttachment> save({required String subjectKind,required String subjectId,required String sourceRevision,required int expectedVersion,required Map<String,dynamic> payload})async{
    saves++;expected=expectedVersion;sent=Map<String,dynamic>.from(jsonDecode(jsonEncode(payload)) as Map);
    if(failSave)throw StateError('Synthetic unknown save result');
    if(holdSave!=null)return await holdSave!.future;
    return TradeDocumentAttachment.fromJson({'version':expectedVersion+1,'payload':payload});
  }
}
class _Fixture{
  String sid='20000000-0000-4000-8000-000000000002';
  late final client=SupabaseClient('https://synthetic.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async=>http.Response(jsonEncode({
    'access_token':_token(sid),'refresh_token':'synthetic-refresh','expires_in':3600,'token_type':'bearer',
    'user':{'id':_actor,'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}}),200,headers:{'content-type':'application/json'},request:request)));
  _Repo? repository;TradeDocumentFormSession? scope;bool? returned;
  Future<void> login()async{await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic-password');}
  Future<void> mount(WidgetTester tester,Map<String,dynamic> workspace,{String kind='invoice',bool mismatched=false})async{
    await tester.runAsync(login);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()async{
      returned=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>TradeDocumentAttachmentEditorPage(
        subjectKind:kind,subjectId:_subject,sourceRevision:_revision,clientOverride:client,repositoryFactory:(client,owned){
          scope=owned;if(mismatched)return TradeDocumentAttachmentRepository(client);
          return repository=_Repo(client,owned,workspace);
        })));
    },child:const Text('parent route'))))));
    await tester.tap(find.text('parent route'));await tester.pumpAndSettle();
  }
  Future<void> close(WidgetTester tester)async{await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(()=>client.dispose().timeout(const Duration(seconds:8)));}
}
void main(){
  setUp(()=>TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  testWidgets('monthly real host opens reviewed input with one bound scope, immutable parties and amounts', (tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace());final touch=tester.widget<TradeDocumentTouchEditorPage>(find.byType(TradeDocumentTouchEditorPage));
      expect(touch.initial.allowAmountEditing,isFalse);expect(touch.canEdit,isTrue);expect(identical(touch.scopeChanges,f.scope),isTrue);
      expect(touch.onEditOwnCompany,isNull);expect(touch.onEditCounterparty,isNull);
      expect(()=>touch.initial.withChanges({'total_amount_yen':1}),throwsFormatException);
      expect(()=>touch.initial.withChanges({'issuer':{'name':'Forged'}}),throwsFormatException);
      expect(f.repository!.loads,1);expect(f.repository!.saves,0);expect(f.returned,isNull);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  testWidgets('explicit save keeps parent pending until result then returns true and exact expected version',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace());final repo=f.repository!;repo.holdSave=Completer<TradeDocumentAttachment>();
      await tester.tap(find.byKey(const Key('trade-touch-save')));await tester.pump();
      expect(repo.saves,1);expect(repo.expected,7);expect(f.returned,isNull);expect(find.byType(TradeDocumentTouchEditorPage),findsOneWidget);
      expect(repo.sent!['issuer'],_payload()['issuer']);expect(repo.sent!['company_seal_snapshot'],_payload()['company_seal_snapshot']);
      repo.holdSave!.complete(TradeDocumentAttachment.fromJson({'version':8,'payload':repo.sent}));await tester.pumpAndSettle();
      expect(f.returned,isTrue);expect(find.byType(TradeDocumentAttachmentEditorPage),findsNothing);expect(find.text('parent route'),findsOneWidget);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  testWidgets('unknown sent save stays open and cannot send a second request',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace());f.repository!.failSave=true;
      await tester.tap(find.byKey(const Key('trade-touch-save')));await tester.pumpAndSettle();
      expect(f.returned,isNull);expect(f.repository!.saves,1);
      expect(tester.widget<FilledButton>(find.byKey(const Key('trade-touch-save'))).onPressed,isNull);
      expect(find.byKey(const Key('trade-touch-error')),findsOneWidget);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  for(final reason in ['readonly','locked']){
    testWidgets('$reason saved marked document never automatically opens editable touch route',(tester)async{
      final f=_Fixture();try{
        await f.mount(tester,_workspace(manage:reason!='readonly',locked:reason=='locked'));
        expect(find.byType(TradeDocumentTouchEditorPage),findsNothing);expect(f.repository!.saves,0);expect(f.returned,isNull);expect(tester.takeException(),isNull);
      }finally{await f.close(tester);}
    });
  }
  testWidgets('legacy saved absence is not upgraded by marked defaults and explicit save keeps original company and source amounts',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace(saved:_payload(marked:false),defaults:_payload()));
      expect(find.byType(TradeDocumentTouchEditorPage),findsNothing);
      final button=find.widgetWithText(FilledButton,'保存して添付');await tester.scrollUntilVisible(button,400,scrollable:find.descendant(of:find.byType(TradeDocumentAttachmentEditorPage),matching:find.byType(Scrollable)).first,maxScrolls:50);await tester.pumpAndSettle();await tester.tap(button);await tester.pumpAndSettle();
      final sent=f.repository!.sent!;for(final key in ['contract_terms','form_fields','counterparty_bank']){expect(sent.containsKey(key),isFalse);}
      expect(sent['issuer'],_payload(marked:false)['issuer']);expect(sent['total_amount_yen'],110000);expect(sent['tax_amount_yen'],10000);expect(f.returned,isTrue);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  testWidgets('source changed invoice without provable historical partner refuses carry and save',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace(changed:true));expect(find.byType(TradeDocumentTouchEditorPage),findsNothing);
      expect(find.textContaining('保存時と現在の相手会社'),findsOneWidget);expect(f.repository!.saves,0);expect(f.returned,isNull);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  for(final binding in ['same','different','missing']){
    testWidgets('source changed payment keeps saved fields only with $binding canonical partner binding',(tester)async{
      final f=_Fixture();try{
        final saved=_payload(order:true)..['counterparty_bank']=_bank();
        (saved['form_fields'] as Map)['work_content']='Saved manual detail';
        final defaults=_payload(order:true)..['counterparty_bank']=_bank(version:2);
        final workspace=_workspace(saved:saved,defaults:defaults,changed:true);
        if(binding!='missing')workspace['canonical_parent_binding']={'parent_id':_subject,'company_id':_company,'partner_company_id':binding=='same'?_partner:'20000000-0000-4000-8000-000000000099'};
        await f.mount(tester,workspace,kind:'payment_certificate');
        if(binding=='same'){
          final touch=tester.widget<TradeDocumentTouchEditorPage>(find.byType(TradeDocumentTouchEditorPage));
          expect(touch.initial.payload['counterparty_bank'],saved['counterparty_bank']);expect(touch.initial.payload['contract_terms'],saved['contract_terms']);
          expect(touch.initial.payload['form_fields'],saved['form_fields']);expect(f.repository!.saves,0);
        }else{expect(find.byType(TradeDocumentTouchEditorPage),findsNothing);expect(f.repository!.saves,0);}
        expect(tester.takeException(),isNull);
      }finally{await f.close(tester);}
    });
  }
  testWidgets('same UID fresh session retires real host and retained save callback cannot submit',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace());final touch=tester.widget<TradeDocumentTouchEditorPage>(find.byType(TradeDocumentTouchEditorPage));
      f.sid='20000000-0000-4000-8000-000000000003';await tester.runAsync(f.login);await tester.pumpAndSettle();
      await expectLater(touch.onSave(touch.initial.payload),throwsStateError);await expectLater(touch.buildPreview(touch.initial.payload),throwsStateError);expect(f.repository!.saves,0);expect(f.returned,isNull);
      expect(find.textContaining('入力を停止しました'),findsOneWidget);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  testWidgets('unbound repository injection fails before any workspace or editable route',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace(),mismatched:true);expect(find.byType(TradeDocumentTouchEditorPage),findsNothing);
      expect(find.textContaining('接続を確認できません'),findsOneWidget);expect(f.repository,isNull);expect(f.returned,isNull);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });
  testWidgets('background during actual submitted save masks editor and late success cannot close parent', (tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace());final repo=f.repository!;repo.holdSave=Completer<TradeDocumentAttachment>();
      await tester.tap(find.byKey(const Key('trade-touch-save')));await tester.pump();expect(repo.saves,1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
      repo.holdSave!.complete(TradeDocumentAttachment.fromJson({'version':8,'payload':repo.sent}));await tester.pumpAndSettle();
      expect(f.returned,isNull);expect(find.textContaining('入力を停止しました'),findsOneWidget);expect(repo.saves,1);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });

  testWidgets('late legacy save never pops a newer sibling route',(tester)async{
    final f=_Fixture();try{
      await f.mount(tester,_workspace(saved:_payload(marked:false)));final repo=f.repository!;repo.holdSave=Completer<TradeDocumentAttachment>();
      final button=find.widgetWithText(FilledButton,'保存して添付');await tester.scrollUntilVisible(button,400,scrollable:find.descendant(of:find.byType(TradeDocumentAttachmentEditorPage),matching:find.byType(Scrollable)).first,maxScrolls:50);await tester.pumpAndSettle();await tester.tap(button);await tester.pump();expect(repo.saves,1);
      final navigator=Navigator.of(tester.element(find.byType(TradeDocumentAttachmentEditorPage)));
      unawaited(navigator.push<void>(MaterialPageRoute(builder:(_)=>const Scaffold(body:Text('newer sibling')))));await tester.pumpAndSettle();
      repo.holdSave!.complete(TradeDocumentAttachment.fromJson({'version':8,'payload':repo.sent}));await tester.pumpAndSettle();
      expect(find.text('newer sibling'),findsOneWidget);expect(f.returned,isNull);expect(repo.saves,1);expect(tester.takeException(),isNull);
    }finally{await f.close(tester);}
  });

}

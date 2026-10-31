import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/expenses/expense_management_repository.dart';
import 'package:sk_works/features/expenses/expense_management_page.dart';
import 'package:sk_works/features/expenses/expense_manager_removal_repository.dart';
import 'package:sk_works/features/expenses/expense_notification_page.dart';

String id(int n)=>'00000000-0000-0000-0000-${n.toString().padLeft(12,'0')}';
class RealLoopbackHttp extends HttpOverrides {}
class NativeWorkspace implements ExpenseManagementAccess {
  NativeWorkspace(this.client);final SupabaseClient client;
  final loaded=List.generate(3,(_)=>Completer<void>());int loads=0;
  @override String? get actor=>id(3);
  @override Future<List<Map<String,dynamic>>> companies()async=>[{'company_id':id(1),'company_name':'Disposable Native fixture'}];
  @override Future<ExpenseReviewWorkspace> load(String company,DateTime month)async{
    final raw=Map<String,dynamic>.from(await client.rpc('expense_manager_removal_workspace',params:{'p_company':company,'p_month':'${month.year}-${month.month.toString().padLeft(2,'0')}-01'}));
    final data=ExpenseReviewWorkspace(raw,company,month)..removalData=raw;
    if(loads<loaded.length)loaded[loads].complete();loads++;return data;
  }
  @override Future<ExpenseReviewCommand?> pending(String company)async=>null;
  @override Future<void> execute(ExpenseReviewCommand command)async=>throw StateError('No review mutation in this bridge');
  @override Future<void> configure(String company,List<String> users,int revision)async=>throw StateError('No configuration mutation in this bridge');
}
class NativeNotice implements ExpenseNoticeSource {
  NativeNotice(this.client);final SupabaseClient client;final loaded=Completer<void>();
  @override String? get actor=>id(9);
  @override Stream<String?> get actorChanges=>const Stream.empty();
  @override Future<Map<String,dynamic>?> load(String notificationId)async{
    final raw=Map<String,dynamic>.from(await client.rpc('expense_manager_removal_notice',params:{'p_notification':notificationId}));
    loaded.complete();return raw;
  }
}
void main(){
  testWidgets('actual frozen Native JSON crosses SDK, removal journal, management UI and applicant notice without a second mutation',(tester)async{
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800,1600));addTearDown(()=>tester.binding.setSurfaceSize(null));
    final transport=IOClient(RealLoopbackHttp().createHttpClient(null)..findProxy=(_)=>'DIRECT');addTearDown(transport.close);
    SupabaseClient sdk(String actor)=>SupabaseClient('http://127.0.0.1:55439','fixture-only',httpClient:transport,
      headers:{'x-fixture-actor':actor,'x-fixture-unknown-first-delete-result':'1'},authOptions:const AuthClientOptions(autoRefreshToken:false));
    final manager=sdk('manager'),applicant=sdk('applicant');addTearDown(manager.dispose);addTearDown(applicant.dispose);
    final events=StreamController<void>.broadcast();addTearDown(events.close);
    Map<String,dynamic>? observed;
    final removals=ExpenseManagerRemovalRepository(actor:()=>id(3),session:()=>id(10),invalidations:events.stream,
      rpc:(name,params)async{final raw=await manager.rpc(name,params:params);if(name=='expense_manager_removal_result')observed=Map<String,dynamic>.from(raw as Map);return raw;});
    addTearDown(removals.dispose);final access=NativeWorkspace(manager);
    await tester.pumpWidget(MaterialApp(home:ExpenseManagementPage(access:access,removals:removals)));
    await tester.runAsync(()=>access.loaded[0].future.timeout(const Duration(seconds:10)));await tester.pumpAndSettle();
    expect(find.text('Native bridge receipt'),findsOneWidget);expect(find.text('削除'),findsOneWidget);
    await tester.ensureVisible(find.text('削除'));await tester.tap(find.text('削除'));await tester.pumpAndSettle();
    expect(find.textContaining('別途訂正が必要'),findsOneWidget);await tester.enterText(find.byType(TextField),'Native bridge only');await tester.tap(find.text('削除を確定'));await tester.pump();
    await tester.runAsync(()=>access.loaded[1].future.timeout(const Duration(seconds:10)));await tester.pumpAndSettle();
    expect(await tester.runAsync(()=>removals.pending(id(1))),isNotNull);
    expect(find.text('削除結果を照会'),findsOneWidget);
    await tester.ensureVisible(find.text('削除結果を照会'));await tester.tap(find.text('削除結果を照会'));await tester.pump();
    await tester.runAsync(()=>access.loaded[2].future.timeout(const Duration(seconds:10)));await tester.pumpAndSettle();
    expect(observed,isNotNull);expect(observed!['claim_id'],id(100));expect(observed!['company_id'],id(1));
    expect(observed!['manager_deleted'],true);expect(observed!['financial_state'],'withdrawn_unfinalized');expect(observed!['correction_required'],false);
    expect(await tester.runAsync(()=>removals.pending(id(1))),null);expect(find.textContaining('管理者削除'),findsWidgets);
    final notification=observed!['notification_id'] as String;
    await tester.runAsync(()=>expectLater(manager.rpc('expense_manager_removal_notice',params:{'p_notification':notification}),throwsA(isA<PostgrestException>())));
    final notice=NativeNotice(applicant);
    await tester.pumpWidget(MaterialApp(home:ExpenseNotificationPage(notificationId:notification,actionKey:'expense_manager_deleted',actionId:observed!['command_id'] as String,source:notice)));
    await tester.runAsync(()=>notice.loaded.future.timeout(const Duration(seconds:10)));await tester.pumpAndSettle();
    expect(find.text('Native bridge receipt'),findsOneWidget);expect(find.text('1234円'),findsOneWidget);expect(find.text('削除を確定'),findsNothing);
    final response=await tester.runAsync(()=>transport.get(Uri.parse('http://127.0.0.1:55439/bridge-info')));
    final info=jsonDecode(response!.body) as Map<String,dynamic>;expect(info['removals'],1);expect(info['notices'],1);
    final trace=info['trace'] as List;expect(trace.where((v)=>v['rpc']=='expense_manager_remove').length,1);
    expect(trace.where((v)=>v['rpc']=='expense_manager_removal_result').length,1);
    expect(info['original']['amount_yen'],1234);expect(info['original']['receipt_object_path'],'retained/bridge-original.png');
    expect(info['synthetic_auth'],true);expect(info['deployable'],false);expect(tester.takeException(),null);
  },skip:Platform.environment['SKO_EXPENSE_NATIVE_BRIDGE']!='fixture-only');
}

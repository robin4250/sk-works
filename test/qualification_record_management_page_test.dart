import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/qualifications/qualification_record_management_page.dart';
import 'package:sk_works/features/qualifications/qualification_record_management_repository.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  Future<QualificationRecordManagementRepository> repository({bool enabled=true})async{
    final events=StreamController<String?>.broadcast(sync:true);
    final repo=QualificationRecordManagementRepository.forTesting(actor:()=> 'actor',authChanges:events.stream,
      rpc:(action,data)async{
        if(action=='capability')return {'version':1,'contract':'qualification_direct_management',
          'company_id':'company','actor_id':'actor','available':enabled};
        if(action=='inspect')return {'version':1,'contract':'qualification_direct_management',
          'snapshot':{'id':'target','company_id':'company','worker_id':'worker',
            'qualification_master_id':'master','certificate_number':'123','issuer':'発行元'}};
        throw StateError('No mutation expected while viewing or cancelling');
      });
    addTearDown(()async{await repo.dispose();await events.close();});return repo;
  }
  testWidgets('management editing shows direct save without approval step',(tester)async{
    final repo=await repository();
    await tester.pumpWidget(MaterialApp(home:QualificationRecordManagementPage(companyId:'company',
      targetId:'target',workerName:'合成従業員',qualificationName:'合成資格',repository:repo)));
    await tester.pumpAndSettle();
    expect(find.text('保存'),findsOneWidget);
    expect(find.textContaining('承認'),findsNothing);
    expect(find.textContaining('申請'),findsNothing);
    expect(find.text('123'),findsOneWidget);
  });
  testWidgets('stopped contract never exposes editing or deletion control',(tester)async{
    final repo=await repository(enabled:false);
    await tester.pumpWidget(MaterialApp(home:QualificationRecordManagementPage(companyId:'company',
      targetId:'target',workerName:'合成従業員',qualificationName:'合成資格',repository:repo)));
    await tester.pumpAndSettle();
    expect(find.text('保存'),findsNothing);
    expect(find.byType(TextField),findsNothing);
    expect(find.textContaining('準備中'),findsOneWidget);
  });
  testWidgets('deletion asks confirmation but does not create approval request',(tester)async{
    final repo=await repository();
    await tester.pumpWidget(MaterialApp(home:QualificationRecordManagementPage(companyId:'company',
      targetId:'target',workerName:'合成従業員',qualificationName:'合成資格',repository:repo,delete:true)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'資格を削除'));await tester.pumpAndSettle();
    expect(find.text('削除'),findsOneWidget);
    expect(find.textContaining('承認'),findsNothing);
    await tester.tap(find.text('戻る'));await tester.pumpAndSettle();
    expect(find.byType(AlertDialog),findsNothing);
  });
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/company_representative_repository.dart';
const actor='00000000-0000-0000-0000-000000000001';
const first='00000000-0000-0000-0000-000000000002';
const second='00000000-0000-0000-0000-000000000003';
class Fixture {
  String currentToken='token-one';
  final changes=StreamController<({String? actor,String? token})>.broadcast(sync:true);
  final calls=<Map<String,dynamic>>[];
  final representatives={first:'甲代表',second:'乙代表'};
  final versions={first:0,second:0};
  bool loseSave=false;
  Completer<void>? readGate;
  late final repo=CompanyRepresentativeRepository.forTesting(
    actor:()=>actor,token:()=>currentToken,changes:changes.stream,
    memberships:()async=>[{'company_id':second,'role':'admin'},{'company_id':first,'role':'owner'}],
    rpc:(action,data)async {
      calls.add({'action':action,...data});
      final id=data['p_company_id'] as String;
      if(action=='save_partner_company_representative') {
        expect((data['p_expected'] as Map)['company_id'],id);
        if((data['p_expected'] as Map)['version']!=versions[id]) { throw StateError('CAS'); }
        representatives[id]=data['p_representative_name'] as String;
        versions[id]=versions[id]!+1;
        if(loseSave) { throw StateError('unknown acknowledgement'); }
      } else { await readGate?.future; }
      return {'company_id':id,'version':versions[id],'contact_updated_at':'fixture',
        'profile':{'name':id==first?'甲会社':'乙会社','representative_name':representatives[id]},'ready':true};
    },
  );
  Future<void> close()async{await repo.dispose();await changes.close();}
}
void main(){
 test('multiple memberships require explicit selected company',()async{
  final f=Fixture();addTearDown(f.close);
  expect((await f.repo.choices()).map((c)=>c.id),[second,first]);
  await expectLater(f.repo.reload(),throwsStateError);
  final chosen=await f.repo.selectCompany(first);
  final saved=await f.repo.save(chosen,'  新しい  代表者  ');
  expect(saved.companyId,first);expect(saved.representative,'新しい 代表者');
  expect(f.representatives[second],'乙代表');
  expect(f.calls.where((c)=>c['action']=='save_partner_company_representative').single['p_company_id'],first);
 }, timeout: const Timeout(Duration(seconds: 30)));
 test('80 codepoints accepted, 81 refused before RPC',()async{
  final f=Fixture();addTearDown(f.close);await f.repo.choices();
  var chosen=await f.repo.selectCompany(first);chosen=await f.repo.save(chosen,'代'*80);
  final count=f.calls.length;await expectLater(f.repo.save(chosen,'代'*81),throwsStateError);expect(f.calls.length,count);
 }, timeout: const Timeout(Duration(seconds: 30)));
 test('foreign choice and old company snapshot refused',()async{
  final f=Fixture();addTearDown(f.close);await f.repo.choices();
  await expectLater(f.repo.selectCompany(actor),throwsStateError);
  final old=await f.repo.selectCompany(first);await f.repo.selectCompany(second);
  await expectLater(f.repo.save(old,'誤接続'),throwsStateError);
 }, timeout: const Timeout(Duration(seconds: 30)));
 test('same actor token ABA stays revoked',()async{
  final f=Fixture();addTearDown(f.close);await f.repo.choices();await f.repo.selectCompany(first);
  f.currentToken='token-two';f.changes.add((actor:actor,token:f.currentToken));
  f.currentToken='token-one';f.changes.add((actor:actor,token:f.currentToken));
  await expectLater(f.repo.reload(),throwsStateError);
 }, timeout: const Timeout(Duration(seconds: 30)));
 test('uncertain save cannot resend before explicit readback',()async{
  final f=Fixture();addTearDown(f.close);await f.repo.choices();
  final old=await f.repo.selectCompany(first);f.loseSave=true;
  await expectLater(f.repo.save(old,'保存された代表'),throwsStateError);
  final count=f.calls.length;await expectLater(f.repo.save(old,'保存された代表'),throwsStateError);expect(f.calls.length,count);
  f.loseSave=false;expect((await f.repo.reload()).representative,'保存された代表');
 }, timeout: const Timeout(Duration(seconds: 30)));
 test('late old company read cannot replace selected company',()async{
  final f=Fixture();addTearDown(f.close);await f.repo.choices();f.readGate=Completer<void>();
  final old=f.repo.selectCompany(first);final oldCheck=expectLater(old,throwsStateError);
  final current=f.repo.selectCompany(second);f.readGate!.complete();await oldCheck;expect((await current).companyId,second);
 }, timeout: const Timeout(Duration(seconds: 30)));
}

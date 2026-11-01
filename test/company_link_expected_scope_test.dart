import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/companies/company_link_scope.dart';

const actor='10000000-0000-4000-8000-000000000001';
const sid='20000000-0000-4000-8000-000000000001';
const a='30000000-0000-4000-8000-000000000001';
const b='30000000-0000-4000-8000-000000000002';
Map<String,dynamic> contexts(List<String> ids)=>{'contract_version':1,'actor_id':actor,'session_id':sid,'companies':[for(final id in ids){'company_id':id,'company_name':id==a?'Company A':'Company B','enabled':true}]};
void main(){
 test('single context preserves usability and binds exact expected company',()async{
  final calls=<Map<String,dynamic>>[];
  final scope=CompanyLinkScope.test(identity:()=>'$actor/$sid',check:()async{},rpc:(name,args)async{if(name=='trade_company_link_contexts')return contexts([a]);calls.add(args);return {'enabled':true,'requests':[]};});
  await scope.loadContexts();expect(scope.company,a);await scope.workspace();expect(calls.single['p_expected_company'],a);await scope.close();
 });
 test('multiple contexts require explicit selection and never take first',()async{
  var calls=0;
  final scope=CompanyLinkScope.test(identity:()=>'$actor/$sid',check:()async{},rpc:(name,args)async{if(name=='trade_company_link_contexts')return contexts([b,a]);calls++;expect(args['p_expected_company'],b);return {'enabled':true,'requests':[]};});
  await scope.loadContexts();expect(scope.company,isNull);await expectLater(scope.workspace(),throwsStateError);expect(calls,0);scope.select(b);await scope.workspace();expect(calls,1);await scope.close();
 });
 test('held old company result is discarded after company switch',()async{
  final held=Completer<Object?>(),started=Completer<void>();
  final scope=CompanyLinkScope.test(identity:()=>'$actor/$sid',check:()async{},rpc:(name,args)async{if(name=='trade_company_link_contexts')return contexts([a,b]);started.complete();return held.future;});
  await scope.loadContexts();scope.select(a);final future=scope.workspace();final assertion=expectLater(future,throwsStateError);await started.future;scope.select(b);held.complete({'enabled':true,'requests':[]});await assertion;await scope.close();
 });
 test('changed SID denies before mutation transport',()async{
  var identity='$actor/$sid',writes=0;
  final scope=CompanyLinkScope.test(identity:()=>identity,check:()async{},rpc:(name,args)async{if(name=='trade_company_link_contexts')return contexts([a]);writes++;return null;});
  await scope.loadContexts();identity='$actor/20000000-0000-4000-8000-000000000002';await expectLater(scope.setEnabled(true),throwsStateError);expect(writes,0);await scope.close();
 });
 test('admission withdrawal blocks request without transport',()async{
  var allowed=true,writes=0;
  final scope=CompanyLinkScope.test(identity:()=>'$actor/$sid',check:()async{if(!allowed)throw StateError('withdrawn');},rpc:(name,args)async{if(name=='trade_company_link_contexts')return contexts([a]);writes++;return null;});
  await scope.loadContexts();allowed=false;await expectLater(scope.request(target:b,role:'customer',month:DateTime(2026,11)),throwsStateError);expect(writes,0);await scope.close();
 });
 test('unknown context fields and foreign selected company reject',()async{
  final scope=CompanyLinkScope.test(identity:()=>'$actor/$sid',check:()async{},rpc:(name,args)async=>{...contexts([a]),'unexpected':true});
  await expectLater(scope.loadContexts(),throwsStateError);expect(()=>scope.select(b),throwsStateError);await scope.close();
 });
}

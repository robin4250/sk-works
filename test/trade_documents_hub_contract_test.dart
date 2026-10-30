import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/trade_documents_hub_contract.dart';
import 'package:sk_works/features/settings/master_feature_availability.dart';

Map<String,dynamic> flags()=>{'site_order_documents':true,
  'standalone_trade_documents_contract_version':1,'trade_documents_master_contract_version':1};
Map<String,dynamic> access()=>{'contract_version':1,'actor_id':'actor','company_id':'company',
  'session_id':'session','role':'manager','master_enabled':true,'can_generate':true,'context_contract_version':1};
void main(){
 test('missing, OFF and unrecognized capability stay fail-closed independently of site archive',(){
  expect(TradeDocumentsHubAvailability.fromFlags({}).enabled,false);
  expect(TradeDocumentsHubAvailability.fromFlags({...flags(),'site_order_documents':false}).enabled,false);
  expect(TradeDocumentsHubAvailability.fromFlags(flags()).enabled,true);
  for(final key in ['standalone_trade_documents_contract_version','trade_documents_master_contract_version']){
   for(final value in [null,0,2,'1',1.0,true]){
    expect(TradeDocumentsHubAvailability.fromFlags({...flags(),key:value}).enabled,false);
   }
  }
  expect(TradeDocumentsHubAvailability.fromFlags({...flags(),'site_order_documents':'true'}).enabled,false);
 });
 test('master availability separately defaults OFF and never uses vehicle absent-ON rule',(){
  final old=MasterFeatureAvailability.fromJson({'vehicle_management':true,'route_assignment':true});
  expect(old.tradeDocumentsSupported,false);expect(old.tradeDocuments,false);
  final supported=MasterFeatureAvailability.fromJson(flags());
  expect(supported.tradeDocumentsSupported,true);expect(supported.tradeDocuments,true);
  expect(MasterFeatureAvailability.fromJson({...flags(),'trade_documents_master_contract_version':'1'}).tradeDocuments,false);
 });
 test('access receipt requires exact actor company SID role and version for each allowed management role',(){
  for(final role in ['owner','admin','manager']){
   expect(()=>TradeDocumentsHubAccess.fromJson({...access(),'role':role},
    actorId:'actor',companyId:'company',sessionId:'session',role:role),returnsNormally);
  }
  for(final key in ['actor_id','company_id','session_id','role','contract_version','context_contract_version','master_enabled','can_generate']){
   final bad=access()..[key]=key.endsWith('version')?'1':key.endsWith('enabled')||key=='can_generate'?false:'foreign';
   expect(()=>TradeDocumentsHubAccess.fromJson(bad,actorId:'actor',companyId:'company',sessionId:'session',role:'manager'),throwsStateError);
  }
  expect(()=>TradeDocumentsHubAccess.fromJson({...access(),'role':'employee'},actorId:'actor',companyId:'company',sessionId:'session',role:'employee'),throwsStateError);
  expect(()=>TradeDocumentsHubAccess.fromJson({...access(),'private_url':'secret'},actorId:'actor',companyId:'company',sessionId:'session',role:'manager'),throwsStateError);
 });
 test('registration role selects supplier for order and customer for acceptance without name matching',(){
  expect(const TradeDocumentsHubParty(id:'id',name:'same name',role:'customer').permits(false),false);
  expect(const TradeDocumentsHubParty(id:'id',name:'same name',role:'subcontractor').permits(true),false);
  expect(const TradeDocumentsHubParty(id:'id',name:'same name',role:'both').permits(true),true);
  expect(const TradeDocumentsHubParty(id:'id',name:'same name',role:'both').permits(false),true);
 });
}

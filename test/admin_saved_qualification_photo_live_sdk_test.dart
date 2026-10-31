import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';

const actor='10000000-0000-0000-0000-000000000001';
const company='10000000-0000-0000-0000-000000000002';
const worker='10000000-0000-0000-0000-000000000003';
const qualification='10000000-0000-0000-0000-000000000004';
const sidA='10000000-0000-0000-0000-000000000005';
const sidB='10000000-0000-0000-0000-000000000006';
class Wire {
  String sid=sidA,role='admin';
  bool current=true,multipleCompanies=false,missingCount=false,truncatedCount=false;
  String returnedCompany=company;
  final requests=<http.Request>[];
  final expiry=DateTime.now().millisecondsSinceEpoch~/1000+3600;
  late final client=SupabaseClient('https://synthetic.invalid','synthetic-public',
    authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient(respond));
  String token(){
    String part(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
    return '${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':sid,'exp':expiry})}.synthetic';
  }
  Future<void> login()async{
    await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic');
    await Future<void>.delayed(Duration.zero);
  }
  Future<http.Response> respond(http.Request request)async{
    requests.add(request);
    final Object? value;
    switch(request.url.path){
      case '/auth/v1/token':
        value={'access_token':token(),'refresh_token':'synthetic','expires_in':3600,'token_type':'bearer',
          'user':{'id':actor,'aud':'authenticated','role':'authenticated',
            'email':'synthetic@example.invalid','app_metadata':{},'user_metadata':{},
            'created_at':'2026-10-31T00:00:00Z'}};
      case '/rest/v1/company_members':value=[{'company_id':company,'role':role},
        if(multipleCompanies){'company_id':worker,'role':'admin'}];
      case '/rest/v1/workers':value=[{'id':worker,'company_id':returnedCompany}];
      case '/rest/v1/rpc/personal_qualification_submission':
        final data=jsonDecode(request.body) as Map;
        expect(data['p_action'],'admin_saved_photo_capability');
        expect(data['p_data'],{'company_id':company});
        value={'version':2,'expected_photo_paths_required':true,'contract':'qualification_admin_saved_photos',
          'company_id':company,'actor_id':actor,'photo_submission_available':true,
          'photo_upload_allowed':false,'max_photos':20,'self_approval_allowed':false};
      default:throw StateError('Unexpected path ${request.url.path}');
    }
    return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json',
      if(request.url.path=='/rest/v1/company_members' && !missingCount)
        'content-range':multipleCompanies?'0-1/2':truncatedCount?'0-0/2':'0-0/1'},request:request);
  }
  AdminSavedQualificationTarget target()=>AdminSavedQualificationTarget({
    'id':qualification,'company_id':company,'worker_id':worker,
    'attachment_path':'synthetic/front','attachment_back_path':null,'attachment_extra_paths':<String>[]});
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  test('real SDK binds selected company and worker with captured bearer',()async{
    final f=Wire();await f.login();f.requests.clear();
    final target=f.target();
    final port=LiveAdminSavedQualificationPort(f.client,target,current:()=>f.current);
    addTearDown(()async{port.dispose();await f.client.dispose();});
    final repository=AdminSavedQualificationSubmissionRepository(port,target);
    expect((await repository.capability()).available,isTrue);
    expect(f.requests.where((r)=>r.method=='POST').map((r)=>r.url.path),
      ['/rest/v1/rpc/personal_qualification_submission']);
    expect(f.requests.every((r)=>r.headers['Authorization']=='Bearer ${f.token()}'),isTrue);
    expect(f.requests.where((r)=>r.url.path.contains('/storage/')),isEmpty);
    expect(f.requests.firstWhere((r)=>r.url.path=='/rest/v1/company_members').headers['Prefer'],contains('count=exact'));
  });
  test('same actor new SID retires old live intent without mutation fallback',()async{
    final f=Wire();await f.login();
    final port=LiveAdminSavedQualificationPort(f.client,f.target(),current:()=>f.current);
    addTearDown(()async{port.dispose();await f.client.dispose();});
    await port.check();f.sid=sidB;await f.login();f.requests.clear();
    await expectLater(port.call('submit',{'id':qualification}),throwsStateError);
    expect(f.requests.where((r)=>r.url.path.endsWith('personal_qualification_submission')),isEmpty);
  });
  test('worker company mismatch, role loss and target retirement reject',()async{
    for(final mode in ['worker','role','target','multipleCompanies','missingCount','truncatedCount']){
      final f=Wire();await f.login();
      final port=LiveAdminSavedQualificationPort(f.client,f.target(),current:()=>f.current);
      if(mode=='worker')f.returnedCompany=worker;
      if(mode=='role')f.role='viewer';
      if(mode=='target')f.current=false;
      if(mode=='multipleCompanies')f.multipleCompanies=true;
      if(mode=='missingCount')f.missingCount=true;
      if(mode=='truncatedCount')f.truncatedCount=true;
      await expectLater(port.call('submit',{'id':qualification}),throwsA(anything));
      expect(f.requests.where((r)=>r.url.path.endsWith('personal_qualification_submission')),isEmpty);
      port.dispose();await f.client.dispose();
    }
  });
}

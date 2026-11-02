import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/master_owner_access.dart';

Map<String,dynamic> masterOwnerFixtureSession({String actor=MasterOwnerAccess.ownerId}) {
  String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':'82000000-0000-0000-0000-000000000002','exp':DateTime.now().millisecondsSinceEpoch ~/ 1000+3600})}.fixture','refresh_token':'fixture-only','token_type':'bearer','expires_in':3600,'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-16T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
Future<SupabaseClient> masterOwnerFixtureClient() async {
  final client=SupabaseClient('https://master-owner-fixture.invalid','public-fixture',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
    if(r.url.host!='master-owner-fixture.invalid' || !r.url.path.endsWith('/rpc/current_master_admin_status')) throw StateError('Unexpected fixture request');
    return http.Response(jsonEncode({'is_master_admin':true}),200,headers:{'content-type':'application/json'},request:r);
  }));
  await client.auth.setInitialSession(jsonEncode(masterOwnerFixtureSession()));
  return client;
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/standalone_trade_document_repository.dart';

const _actor='00000000-0000-0000-0000-000000000001';
const _company='00000000-0000-0000-0000-000000000002';
const _partner='00000000-0000-0000-0000-000000000003';
String _jwt() {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':_actor,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.fixture';
}
class _Fixture extends http.BaseClient {
  final String token=_jwt();
  final calls=<http.BaseRequest>[];
  bool multi=false;
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    final path=request.url.path;
    Object value;
    if(path.endsWith('/auth/v1/token')) {
      value={'access_token':token,'refresh_token':'fixture-refresh','expires_in':3600,'token_type':'bearer',
        'user':{'id':_actor,'aud':'authenticated','role':'authenticated','email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'}};
    } else {
      expect(request.headers['Authorization']??request.headers['authorization'],'Bearer $token');
      if(path.endsWith('/company_members')) {
        expect(request.url.queryParameters['user_id'],'eq.$_actor');
        value=[{'company_id':_company,'role':'admin'},if(multi){'company_id':_partner,'role':'owner'}];
      } else if(path.endsWith('/trade_company_contact_workspace')) {
        value=[{'id':_partner,'trade_role':'both','name':'登録相手','address':'相手住所','representative_name':'相手代表'}];
      } else if(path.endsWith('/read_partner_company_profile')) {
        expect(jsonDecode((request as http.Request).body)['p_company_id'],_company);
        value={'company_id':_company,'profile':{'name':'自社会社','address':'自社住所','representative_name':'自社代表'}};
      } else if(path.endsWith('/companies')) {
        expect(request.url.queryParameters['id'],'eq.$_company');
        value={'id':_company,'name':'自社会社','company_seal_enabled':true,'company_seal_style':'legacy'};
      } else if(path.endsWith('/company_uploaded_seal_settings')) {
        value={'company_id':_company,'company_name':'自社会社','enabled':false};
      } else if(path.endsWith('/trade_document_template')) {
        value={'version':0,'payload':{'work_name':'初期文','work_address':'初期場所'}};
      } else { throw StateError('Unexpected SDK request $path'); }
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))),200,
      headers:{'content-type':'application/json'},request:request);
  }
}
void main() {
  test('missing session refuses any company before SDK reads; dispose is idempotent', () async {
    final fixture=_Fixture();
    final client=SupabaseClient('https://fixture.invalid','fixture-public',httpClient:fixture,
      authOptions:const AuthClientOptions(autoRefreshToken:false));
    final repository=StandaloneTradeDocumentRepository(client);
    try {
      await expectLater(repository.load(tradeCompanyId:_partner,acceptance:false),throwsStateError);
      expect(fixture.calls,isEmpty);
      final closing=repository.dispose();expect(identical(closing,repository.dispose()),true);await closing;
      expect(repository.verify,throwsStateError);
    } finally {await repository.dispose();await client.dispose();}
  });
  test('read-only registration load pins the selected company and captured token', () async {
    final fixture=_Fixture();
    final client=SupabaseClient('https://fixture.invalid','fixture-public',httpClient:fixture,
      authOptions:const AuthClientOptions(autoRefreshToken:false));
    await client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture-password');
    final repository=StandaloneTradeDocumentRepository(client);
    try {
      final value=await repository.load(tradeCompanyId:_partner,acceptance:true);
      expect(value['company_id'],_company);expect(value['trade_company_id'],_partner);
      expect((value['issuer'] as Map)['representative_name'],'自社代表');
      expect((value['counterparty'] as Map)['name'],'登録相手');
      expect(fixture.calls.where((r)=>r.method=='POST'&&!r.url.path.contains('/auth/')).every((r)=>
        ['trade_company_contact_workspace','read_partner_company_profile','company_uploaded_seal_settings','trade_document_template'].any((name)=>r.url.path.endsWith('/$name'))),true);
      repository.invalidate();expect(repository.verify,throwsStateError);
    } finally {await repository.dispose();await client.dispose();}
  });
  test('multiple memberships and a foreign registration refuse before profile or seal reads', () async {
    for(final multiple in [true,false]) {
      final fixture=_Fixture()..multi=multiple;
      final client=SupabaseClient('https://fixture.invalid','fixture-public',httpClient:fixture,
        authOptions:const AuthClientOptions(autoRefreshToken:false));
      await client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture-password');
      final repository=StandaloneTradeDocumentRepository(client);
      try {
        await expectLater(repository.load(tradeCompanyId:multiple?_partner:_actor,acceptance:false),throwsStateError);
        expect(fixture.calls.any((r)=>r.url.path.endsWith('/read_partner_company_profile')),false);
      } finally {await repository.dispose();await client.dispose();}
    }
  });
}

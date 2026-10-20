import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/domain/company_uploaded_seal_png.dart';
import 'package:sk_works/features/settings/company_seal_png_repository.dart';
import 'package:sk_works/features/settings/company_seal_png_uploader.dart';
import 'package:sk_works/features/shared/company_seal_current_preview.dart';

const company = (companyId:'00000000-0000-0000-0000-000000000001',name:'検証株式会社');
const actor='00000000-0000-0000-0000-000000000002';
const encoded='iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
class FakeSource implements CompanySealPngSource {
  FakeSource({this.available=true});
  final bool available;
  int saves=0;
  @override Future<CompanySealPngSettings> load(UploadedSealCompany context) async => CompanySealPngSettings(company:context,available:available);
  @override Future<CompanySealPngSettings> save(CompanySealPngSettings settings,{CompanyUploadedSealPng? png,required bool enabled}) async {
    saves++;throw StateError('unexpected save');
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('missing backend disables PNG registration and never reports save success',(tester)async{
    final source=FakeSource(available:false);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:CompanySealPngUploader(company:company,source:source)))));
    await tester.pumpAndSettle();
    expect(find.text('PNG登録の保存準備中です。既存の角印は引き続き使えます。'),findsOneWidget);
    final button=tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'PNGファイルを選ぶ'));
    expect(button.onPressed,isNull);expect(source.saves,0);
  });
  testWidgets('invalid PNG selection cannot reach save',(tester)async{
    final source=FakeSource();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:CompanySealPngUploader(company:company,source:source,pickPng:()async=>Uint8List(70))))));
    await tester.pumpAndSettle();await tester.tap(find.text('PNGファイルを選ぶ'));await tester.pumpAndSettle();
    expect(find.text('PNG画像を選択してください。'),findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'このPNGを保存して使用')).onPressed,isNull);
    expect(source.saves,0);
  });
  test('repository confirms company revision enabled flag and frozen bytes; absent RPC cannot save',()async{
    var missing=false, revision=0;final calls=<http.Request>[];
    Map<String,dynamic> settings()=>{'company_id':company.companyId,'company_name':company.name,'available':true,
      'enabled':revision>0,'revision':revision,'version_id':revision==0?null:'00000000-0000-0000-0000-000000000003',
      'png_base64':revision==0?null:encoded,'png_sha256':revision==0?null:'30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc',
      'width':revision==0?null:32,'height':revision==0?null:32};
    final client=SupabaseClient('https://seal.invalid','synthetic',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request)async{
      calls.add(request);Object? body;
      if(request.url.path=='/auth/v1/token'){
        String tokenPart(Object value)=>base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
        body={'access_token':'${tokenPart({'alg':'HS256','typ':'JWT'})}.${tokenPart({'sub':actor,'exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.c3ludGhldGlj',
          'refresh_token':'synthetic','token_type':'bearer','expires_in':3600,
          'user':{'id':actor,'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}};
      }else if(request.url.path=='/rest/v1/rpc/company_uploaded_seal_settings'){
        if(missing)return http.Response(jsonEncode({'code':'PGRST202','message':'missing RPC'}),404,headers:{'content-type':'application/json'});
        body=settings();
      }else if(request.url.path=='/rest/v1/rpc/company_current_uploaded_seal'){
        if(missing)return http.Response(jsonEncode({'code':'PGRST202','message':'missing RPC'}),404,headers:{'content-type':'application/json'});
        body={'company_id':company.companyId,'company_name':company.name,'snapshot':{'version':2,'style':'uploaded_png',
          'company_id':company.companyId,'name':company.name,'png_version_id':'00000000-0000-0000-0000-000000000003',
          'png_base64':encoded,'png_sha256':settings()['png_sha256']}};
      }else if(request.url.path=='/rest/v1/rpc/save_company_uploaded_seal'){
        final params=jsonDecode(request.body) as Map;
        expect(params['p_company_id'],company.companyId);expect(params['p_expected_name'],company.name);expect(params['p_expected_revision'],0);
        expect(params['p_png_base64'],encoded);expect(params['p_enabled'],true);
        revision++;body=settings();
      }else{throw StateError('unexpected request');}
      return http.Response(jsonEncode(body),200,headers:{'content-type':'application/json'});
    }));
    try{
      await client.auth.signInWithPassword(email:'test@example.invalid',password:'synthetic');
      final repo=CompanySealPngRepository.forTesting(client);final initial=await repo.load(company);
      final saved=await repo.save(initial,png:CompanyUploadedSealPng.fromBase64(encoded),enabled:true);
      expect(saved.png!.base64,encoded);expect(saved.revision,1);
      final current=await companyWithCurrentUploadedSeal(client,{'id':company.companyId,'name':company.name,'company_seal_style':'legacy'},company.companyId);
      expect(current['company_seal_uploaded_snapshot'],isNotNull);
      missing=true;
      final fallback=await companyWithCurrentUploadedSeal(client,{'id':company.companyId,'name':company.name,'company_seal_style':'legacy'},company.companyId);
      expect(fallback.containsKey('company_seal_uploaded_snapshot'),isFalse);
      final unavailable=await repo.load(company);expect(unavailable.available,isFalse);
      calls.clear();await expectLater(repo.save(unavailable,enabled:true),throwsStateError);expect(calls,isEmpty);
    }finally{await client.dispose();}
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/line_historical_invoice_bridge_repository.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late LineHistoricalInvoiceBridgeRepository repository;
  final requests = <Map<String,dynamic>>[];
  Completer<void>? gate, arrived;
  var failures = 0;
  Future<void> session(String actor) async { await client.auth.setInitialSession(jsonEncode({
    'access_token': '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp':4102444800,'sub':actor})))}.test',
    'refresh_token':'fixture','token_type':'bearer','expires_in':3600,
    'user':User(id:actor,appMetadata:const {},userMetadata:const {},aud:'authenticated',createdAt:'2026-01-01T00:00:00Z').toJson(),
  })); }
  setUp(() async {
    requests.clear();gate=null;arrived=null;failures=0;
    server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
    server.listen((request) async {
      final body=Map<String,dynamic>.from(jsonDecode(await utf8.decoder.bind(request).join()) as Map);
      requests.add(body);
      if(arrived != null && !arrived!.isCompleted) arrived!.complete();
      if(gate != null) await gate!.future;
      request.response.headers.contentType=ContentType.json;
      if(failures>0){failures--;request.response.statusCode=503;request.response.write(jsonEncode({'message':'fixture temporary failure','code':'fixture'}));}
      else{request.response.write(jsonEncode({'quote_id':'quote','invoices':[],'status':'draft','issued':false,'approved':false}));}
      await request.response.close();
    });
    client=SupabaseClient('http://127.0.0.1:${server.port}','fixture',authOptions:const AuthClientOptions(autoRefreshToken:false));
    await session('actor');repository=LineHistoricalInvoiceBridgeRepository(client);
  });
  tearDown(() async {if(gate!=null && !gate!.isCompleted) gate!.complete();await client.dispose();await server.close(force:true);});
  test('changed session rejects an in-flight historical workspace', () async {
    gate=Completer<void>();arrived=Completer<void>();
    final loading=repository.load('quote');
    await arrived!.future;
    await session('other');gate!.complete();gate=null;
    await expectLater(loading,throwsStateError);
    expect(requests.single,{'p_quote_id':'quote'});
  });
  test('failed creation retries the same deeply captured command', () async {
    final terms=[{'site_id':'site','customer_id':'customer','welfare_rate_bps':0}];
    final command=repository.command({'p_quote_id':'quote','p_site_terms':terms,'p_tax_rate_bps':0},'preview');
    terms.single['customer_id']='changed';
    expect((command['p_site_terms'] as List).single['customer_id'],'customer');
    failures=1;
    await expectLater(repository.create(command),throwsA(isA<PostgrestException>()));
    final result=await repository.create(command);
    expect(result['status'],'draft');
    expect(requests.length,2);expect(requests.first,requests.last);
    expect(requests.last['p_preview_confirmed'],true);
  });
}

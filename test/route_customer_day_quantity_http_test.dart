import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/route_billing/route_customer_day_quantity_repository.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('checkout submission sends the captured day, complete saved IDs and expected versions, rejecting malformed receipts',
    () => HttpOverrides.runWithHttpOverrides(() async {
      const actor = '11111111-1111-4111-8111-111111111111';
      final calls = <Map<String, dynamic>>[];
      var malformed = false;
      var diagnosticsAvailable = true;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4,0);
      server.listen((request) async {
        Object response;
        if (request.uri.path == '/auth/v1/token') {
          String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=','');
          response = {'access_token': '${encode({'alg':'HS256'})}.${encode({'sub':actor,'exp':DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture',
            'refresh_token':'fixture','token_type':'bearer','expires_in':3600,
            'user':{'id':actor,'aud':'authenticated','role':'authenticated','email':'fixture@example.test',
              'app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}};
        } else {
          final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String,dynamic>;
          calls.add({'path':request.uri.path,'body':body});
          if (request.uri.path.endsWith('/route_customer_day_quantity_candidates')) {
            response = {'unresolved_count':0,'customers':[
              {'customer_id':'a','customer_name':'A社','report_ids':['a1','a2'],'visits':[{'site_name':'現場A'}],
                'version':2,'status':'pending','requested_quantity':0.5,'quantity':0.5},
              {'customer_id':'b','customer_name':'B社','report_ids':['b1'],'visits':[{'site_name':'現場B'}],
                'version':1,'status':'approved','requested_quantity':1,'quantity':0.5},
            ]};
          } else if (request.uri.path.endsWith('/route_customer_day_quantity_diagnostics')) {
            if (!diagnosticsAvailable) request.response.statusCode = 500;
            response = diagnosticsAvailable
                ? {'completed_report_count':5,'eligible_report_count':3,
                    'unresolved_customer_count':0,'missing_source_count':2,
                    'waiting_checkout_count':0}
                : {'message':'diagnostics unavailable'};
          } else if (request.uri.path.endsWith('/submit_route_customer_day_allocations_checked')) {
            response = [{'customer_id':'a','status':'pending'},
              {'customer_id':malformed ? 'a' : 'b','status':'approved'}];
          } else {
            request.response.statusCode = 500;response = {'message':'unexpected request'};
          }
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));await request.response.close();
      });
      final client = SupabaseClient('http://127.0.0.1:${server.port}','fixture',
        authOptions: const AuthClientOptions(autoRefreshToken:false));
      try {
        await client.auth.signInWithPassword(email:'fixture@example.test',password:'fixture');
        final repository = RouteCustomerDayQuantityRepository(client);
        final date = DateTime(2026,10,12);
        final day = await repository.load('worker',date);
        expect(day.customers[1].approvedQuantity,0.5);
        expect(day.diagnostics?.missingSourceCount,2);
        expect(calls.last['path'],'/rest/v1/rpc/route_customer_day_quantity_diagnostics');
        expect(calls.last['body'],{'p_worker_id':'worker','p_work_date':'2026-10-12'});
        diagnosticsAvailable = false;
        final fallback = await repository.load('worker',date);
        expect(fallback.diagnostics,isNull);
        expect(fallback.customers.map((c)=>c.id),['a','b']);
        expect(fallback.unresolvedCount,0);
        await repository.submit('worker',date,day,{'a':0.5,'b':1});
        expect(calls.last['body'],{
          'p_worker_id':'worker','p_work_date':'2026-10-12','p_report_ids':['a1','a2','b1'],
          'p_allocations':[{'customer_id':'a','quantity':0.5},{'customer_id':'b','quantity':1.0}],
          'p_expected_versions':{'a':2,'b':1},
        });
        final before = calls.length;
        await expectLater(repository.submit('worker',date,day,{'a':1}),throwsStateError);
        expect(calls.length,before);
        malformed = true;
        await expectLater(repository.submit('worker',date,day,{'a':0.5,'b':1}),throwsStateError);
      } finally {
        await client.dispose();await server.close(force:true);
      }
    },_RealHttp()));
}

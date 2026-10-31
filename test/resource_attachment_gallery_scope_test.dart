import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';

class _SessionFixture {
  static const actor = '20000000-0000-0000-0000-000000000001';
  String sid = '20000000-0000-0000-0000-000000000002';
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final requests = <http.Request>[];
  Completer<void>? logoutRelease;
  Future<http.Response> Function(http.Request)? metadata;
  late final client = SupabaseClient('https://synthetic-gallery.invalid', 'synthetic-public',
    authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/auth/v1/logout') {
        if (logoutRelease != null) { await logoutRelease!.future; }
        return http.Response('{}', 204, request: request);
      }
      if (request.url.path != '/auth/v1/token' && metadata != null) { return metadata!(request); }
      expect(request.url.path, '/auth/v1/token');
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return http.Response(jsonEncode({'access_token': '${part({'alg':'HS256'})}.${part({'sub':actor,'session_id':sid,'exp':expiry})}.synthetic',
        'refresh_token':'synthetic','token_type':'bearer','expires_in':3600,'user':{
          'id':actor,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z','app_metadata':{},'user_metadata':{}}}),
        200, headers: {'content-type':'application/json'}, request: request);
    }));
  Future<void> login(String value) async {
    sid = value; await client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic');
    await Future<void>.delayed(Duration.zero);
  }
}
void main() {
  for (final qualifications in [true, false]) {
    test('${qualifications ? 'qualification' : 'document'} read lease rejects actual SDK same-UID SID ABA and adds zero reads', () async {
      final fixture = _SessionFixture(); addTearDown(fixture.client.dispose);
      await fixture.login('20000000-0000-0000-0000-000000000002');
      final before = fixture.requests.length;
      final capture = qualifications ? QualificationCloudRepository.forTesting(fixture.client).captureAttachmentReadScope
          : WorkerDocumentRepository.forTesting(fixture.client).captureAttachmentReadScope;
      final lease = await capture(); expect(lease(), isTrue); expect(fixture.requests.length, before);
      final original = fixture.client.auth.currentSession!.accessToken;
      await fixture.login('20000000-0000-0000-0000-000000000003'); expect(lease(), isFalse);
      await fixture.login('20000000-0000-0000-0000-000000000002');
      expect(fixture.client.auth.currentSession!.accessToken, original); expect(lease(), isFalse);
      expect((await capture())(), isTrue);
      expect(fixture.requests.every((request) => request.url.path == '/auth/v1/token'), isTrue);
    });
    test('${qualifications ? 'qualification' : 'document'} read lease retires synchronously at existing logout intent', () async {
      final fixture = _SessionFixture(); addTearDown(fixture.client.dispose);
      await fixture.login('20000000-0000-0000-0000-000000000002');
      final lease = qualifications ? await QualificationCloudRepository.forTesting(fixture.client).captureAttachmentReadScope()
          : await WorkerDocumentRepository.forTesting(fixture.client).captureAttachmentReadScope();
      fixture.logoutRelease = Completer<void>();
      final logout = AppAuthMutationGateway.forClient(fixture.client).signOut();
      expect(lease(), isFalse, reason: 'no late image may cross logout admission while the SDK is still pending');
      fixture.logoutRelease!.complete(); await logout; expect(lease(), isFalse);
    });
  }
  for (final qualifications in [true, false]) {
    test('${qualifications ? 'qualification' : 'document'} loaded metadata preserves company filters and gallery boundaries', () async {
      final fixture = _SessionFixture(); addTearDown(fixture.client.dispose);
      await fixture.login('20000000-0000-0000-0000-000000000002');
      fixture.requests.clear();
      fixture.metadata = (request) async {
        Object? value;
        switch (request.url.path.split('/').last) {
          case 'ensure_current_user_worker': value = 'worker';
          case 'company_members': value = [{'company_id':'company','role':'employee'}];
          case 'workers': value = request.url.queryParameters['select'] == 'name' ? {'name':'合成社員'} : [{'id':'worker','company_id':'company','name':'合成社員','status':'active'}];
          case 'qualification_master': value = [{'id':'master','name':'合成資格'}];
          case 'worker_qualifications': value = [{'id':'qualification','company_id':'company','worker_id':'worker','qualification_master_id':'master','attachment_path':'synthetic.png'}];
          case 'document_requirements': value = [{'id':'requirement','company_id':'company','name':'合成書類','is_active':true,'is_required':true,'archived_at':null}];
          case 'worker_document_exemption': value = {'capability_version':1,'can_manage':false,'items':[]};
          case 'worker_document_statuses': value = [{'id':'status','company_id':'company','worker_id':'worker','requirement_id':'requirement','status':'submitted','attachment_path':'synthetic.png','attachment_paths':['synthetic.png']}];
          default: throw StateError('unexpected metadata fixture read');
        }
        return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'},request:request);
      };
      if (qualifications) {
        final data = await QualificationCloudRepository.forTesting(fixture.client).loadOwnQualificationWorkspace();
        expect((data['worker'] as Map)['company_id'],'company');
        expect((data['qualifications'] as List).single['company_id'],'company');
        expect(fixture.requests.map((request)=>request.url.path.split('/').last),
          ['ensure_current_user_worker','company_members','workers','qualification_master','worker_qualifications']);
        final read=fixture.requests.last; expect(read.url.queryParameters['select'],contains('company_id'));
        expect(read.url.queryParameters['company_id'],'eq.company'); expect(read.url.queryParameters['worker_id'],'eq.worker');
        expect(fixture.requests[2].url.queryParameters['company_id'],'eq.company');
        expect(fixture.requests[2].url.queryParameters['id'],'eq.worker');
        final metadata=fixture.metadata!;fixture.requests.clear();
        fixture.metadata=(request) async => request.url.path.endsWith('/workers')
          ? http.Response(jsonEncode([{'id':'worker','company_id':'foreign-company','name':'合成社員'}]),200,headers:{'content-type':'application/json'},request:request)
          : metadata(request);
        await expectLater(QualificationCloudRepository.forTesting(fixture.client).loadOwnQualificationWorkspace(),throwsStateError);
        expect(fixture.requests.any((request)=>request.url.path.endsWith('/worker_qualifications')),isFalse);
      } else {
        final data = await WorkerDocumentRepository.forTesting(fixture.client).loadOwnDocuments();
        expect(data['workers']!.single['company_id'],'company'); expect(data['statuses']!.single['company_id'],'company');
        expect(fixture.requests.map((request)=>request.url.path.split('/').last),
          ['company_members','ensure_current_user_worker','workers','company_members','document_requirements','worker_document_exemption','workers','worker_document_statuses']);
        expect(fixture.requests.first.method, 'GET');
        expect(fixture.requests.first.url.queryParameters['limit'], '2');
        expect(fixture.requests[2].url.queryParameters['company_id'], 'eq.company');
        expect(fixture.requests[2].url.queryParameters['user_id'], 'eq.${fixture.client.auth.currentUser!.id}');
        expect(fixture.requests[2].url.queryParameters['status'], 'eq.active');
        for (final read in fixture.requests.where((request)=>request.url.path.endsWith('/worker_document_statuses') ||
            request.url.path.endsWith('/workers') && request.url.queryParameters['select'] != 'name')) {
          expect(read.url.queryParameters['select'],contains('company_id')); expect(read.url.queryParameters['company_id'],'eq.company');
        }
      }
      expect(fixture.requests.every((request)=>request.method=='GET'||request.url.path.contains('/rpc/')),isTrue);
    });
  }

}

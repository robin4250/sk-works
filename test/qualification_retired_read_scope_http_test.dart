import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/qualifications/qualification_cloud_repository.dart';
import 'package:sk_works/features/qualifications/qualification_certificate_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const otherActor = '10000000-0000-0000-0000-000000000002';
const company = '20000000-0000-0000-0000-000000000001';
const otherCompany = '20000000-0000-0000-0000-000000000002';
const worker = '30000000-0000-0000-0000-000000000001';
const otherWorker = '30000000-0000-0000-0000-000000000002';
const master = '40000000-0000-0000-0000-000000000001';
const qualification = '50000000-0000-0000-0000-000000000001';
const sid = '60000000-0000-0000-0000-000000000001';
const sid2 = '60000000-0000-0000-0000-000000000002';
const path = '$company/$worker/$qualification/front.jpg';

class _ObservedAuth extends GoTrueClient {
  _ObservedAuth(this.delegate, this.events) : super(url: 'https://observer.invalid', autoRefreshToken: false);
  final GoTrueClient delegate;
  final Stream<AuthState> events;
  @override Session? get currentSession => delegate.currentSession;
  @override User? get currentUser => delegate.currentUser;
  @override Stream<AuthState> get onAuthStateChange => events;
}
class _Client extends SupabaseClient {
  _Client(http.Client httpClient) : super('https://qualification-read.synthetic.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: httpClient);
  _ObservedAuth? observed;
  GoTrueClient get originalAuth => super.auth;
  @override GoTrueClient get auth => observed ?? super.auth;
}

class _Fixture {
  late _Client client;
  late QualificationCloudRepository cloud;
  late QualificationCertificateRepository certificates;
  final requests = <http.Request>[];
  List<Map<String, dynamic>> members = [{'company_id': company, 'role': 'viewer'}];
  List<Map<String, dynamic>> workers = [
    {'id': worker, 'company_id': company, 'user_id': actor, 'name': 'Synthetic person', 'affiliation': 'employee', 'status': 'inactive'},
  ];
  List<Map<String, dynamic>> masters = [{'id': master, 'company_id': company, 'name': 'Synthetic qualification', 'is_active': true}];
  List<Map<String, dynamic>> qualifications = [
    {'id': qualification, 'company_id': company, 'worker_id': worker, 'qualification_master_id': master,
      'certificate_number': 'KEEP', 'attachment_path': path, 'attachment_back_path': null,
      'attachment_extra_paths': <String>[], 'notes': 'original'},
  ];
  Object permissions = <String, dynamic>{'can_manage_people': false};
  bool ignoreWorkerFilters = false, ignoreQualificationFilters = false, missingExtras = false;
  String? denyPath, waitPath;
  int qualificationReads = 0;
  Completer<void>? wait;
  final started = Completer<void>();
  Future<void> login({String? sessionId = sid, String claimActor = actor}) async {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.originalAuth.setInitialSession(jsonEncode({
      'access_token': '${part({'alg': 'HS256'})}.${part({'sub': claimActor, if (sessionId != null) 'session_id': sessionId, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
      'refresh_token': 'synthetic-$sessionId', 'token_type': 'bearer', 'expires_in': 3600,
      'user': {'id': actor, 'aud': 'authenticated', 'created_at': '2026-11-01T00:00:00Z',
        'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}},
    }));
  }
  static Future<_Fixture> create() async {
    final f = _Fixture();
    f.client = _Client(MockClient((r) async {
      f.requests.add(r);
      final endpoint = r.url.path.split('/').last;
      if (f.waitPath != null && r.url.path.contains(f.waitPath!) && f.wait != null) {
        if (!f.started.isCompleted) f.started.complete();
        await f.wait!.future;
      }
      Object? value;
      var code = 200;
      if (r.url.path == f.denyPath) {
        code = 403; value = {'code': '42501', 'message': 'synthetic denied'};
      } else if (r.url.path.contains('/storage/v1/object/sign/')) {
        value = {'signedURL': '/object/sign/qualification-certificates/synthetic?token=signed'};
      } else {
        switch (endpoint) {
          case 'company_members': value = f.members;
          case 'current_feature_permissions': value = f.permissions;
          case 'ensure_current_user_worker': value = worker;
          case 'workers':
            var rows = f.workers;
            if (!f.ignoreWorkerFilters) {
              for (final key in ['id', 'user_id', 'company_id']) {
                final filter = r.url.queryParameters[key];
                if (filter != null) rows = rows.where((row) => 'eq.${row[key]}' == filter).toList();
              }
            }
            value = rows;
            if (r.headers['Accept']?.contains('application/vnd.pgrst.object+json') == true && rows.length == 1) value = rows.single;
          case 'qualification_master': value = f.masters;
          case 'worker_qualifications':
            if (r.method != 'GET') { value = {...f.qualifications.single, ...(jsonDecode(r.body) as Map)}; break; }
            f.qualificationReads++;
            if (f.missingExtras && (r.url.queryParameters['select'] ?? '').contains('attachment_extra_paths')) {
              code = 400; value = {'code': '42703', 'message': 'column attachment_extra_paths does not exist'};
            } else {
              var rows = f.qualifications;
              if (!f.ignoreQualificationFilters) {
                for (final key in ['id', 'worker_id', 'company_id']) {
                  final filter = r.url.queryParameters[key];
                  if (filter != null) rows = rows.where((row) => 'eq.${row[key]}' == filter).toList();
                }
              }
              value = rows;
            }
          default: throw StateError('Unexpected endpoint ${r.url.path}');
        }
      }
      return http.Response(jsonEncode(value), code, headers: {'content-type': 'application/json'}, request: r);
    }));
    await f.login();
    f.cloud = QualificationCloudRepository.forTesting(f.client);
    f.certificates = QualificationCertificateRepository.forTesting(f.client);
    return f;
  }
  Future<Map<String, dynamic>> read(String kind) => kind == 'cloud' ? cloud.loadAll() : certificates.loadAll();
  Future<String> photo(String kind, String storedPath) => kind == 'cloud'
      ? cloud.createOwnQualificationPhotoUrl(qualificationId: qualification, storagePath: storedPath)
      : certificates.createSignedUrl(storedPath);
  Future<void> close() async { client.observed?.dispose(); await client.dispose(); }
}

void main() {
  for (final kind in ['cloud', 'certificate']) {
    test('$kind inactive own history does not initialize or write and keeps originals', () async {
      final f = await _Fixture.create(); addTearDown(f.close);
      final bearer = 'Bearer ${f.client.auth.currentSession!.accessToken}';
      final original = jsonEncode(f.qualifications);
      final result = await f.read(kind);
      expect((result['workers'] as List).single['status'], 'inactive');
      expect((result['qualifications'] as List).single['attachment_path'], path);
      expect(jsonEncode(f.qualifications), original);
      expect(f.requests.any((r) => r.url.path.endsWith('ensure_current_user_worker')), false);
      expect(f.requests.every((r) => r.method == 'GET' || r.url.path.endsWith('current_feature_permissions')), true);
      expect(f.requests.every((r) => r.headers['Authorization'] == bearer), true);
      final identity = f.requests.where((r) => r.url.path.endsWith('/workers'));
      expect(identity.every((r) => r.url.queryParameters['limit'] == '2' && r.url.queryParameters['user_id'] == 'eq.$actor'), true);
    });
    test('$kind manager roster keeps other active and inactive workers', () async {
      final f = await _Fixture.create(); addTearDown(f.close);
      f.members.single['role'] = 'admin'; f.permissions = {'can_manage_people': true};
      f.workers.add({'id': otherWorker, 'company_id': company, 'user_id': otherActor, 'name': 'Other person', 'status': 'active'});
      expect((await f.read(kind))['workers'], hasLength(2));
      expect(f.requests.where((r) => r.url.path.endsWith('/workers')).every((r) => !r.url.queryParameters.containsKey('status')), true);
    });
    for (final fault in ['missing', 'duplicate', 'foreign-person', 'foreign-company', 'invalid-id', 'unknown-status', 'mixed-unknown-duplicate']) {
      test('$kind own identity $fault refuses private qualification reads', () async {
        final f = await _Fixture.create(); addTearDown(f.close); f.ignoreWorkerFilters = true;
        switch (fault) {
          case 'missing': f.workers.clear();
          case 'duplicate': f.workers.add(Map.of(f.workers.single));
          case 'foreign-person': f.workers.single['user_id'] = otherActor;
          case 'foreign-company': f.workers.single['company_id'] = otherCompany;
          case 'invalid-id': f.workers.single['id'] = 'invalid';
          case 'unknown-status': f.workers.single['status'] = 'unknown';
          case 'mixed-unknown-duplicate': f.workers.add({...f.workers.single, 'id': otherWorker, 'status': 'unknown'});
        }
        await expectLater(f.read(kind), throwsStateError);
        expect(f.qualificationReads, 0);
      });
    }
    for (final fault in ['missing-role', 'unknown-role', 'company-id', 'duplicate', 'missing-sid', 'bad-sid', 'token-actor']) {
      test('$kind initial $fault refuses before private data', () async {
        final f = await _Fixture.create(); addTearDown(f.close);
        switch (fault) {
          case 'missing-role': f.members.single.remove('role');
          case 'unknown-role': f.members.single['role'] = 'unknown';
          case 'company-id': f.members.single['company_id'] = 'invalid';
          case 'duplicate': f.members.add(Map.of(f.members.single));
          case 'missing-sid': await f.login(sessionId: null);
          case 'bad-sid': await f.login(sessionId: 'unknown');
          case 'token-actor': await f.login(claimActor: otherActor);
        }
        await expectLater(f.read(kind), throwsStateError);
        expect(f.qualificationReads, 0);
      });
    }
    for (final fault in ['company', 'worker', 'id', 'master-id', 'duplicate']) {
      test('$kind returned qualification $fault mismatch is rejected', () async {
        final f = await _Fixture.create(); addTearDown(f.close); f.ignoreQualificationFilters = true;
        switch (fault) {
          case 'company': f.qualifications.single['company_id'] = otherCompany;
          case 'worker': f.qualifications.single['worker_id'] = otherWorker;
          case 'id': f.qualifications.single['id'] = 'unknown';
          case 'master-id': f.qualifications.single['qualification_master_id'] = null;
          case 'duplicate': f.qualifications.add(Map.of(f.qualifications.single));
        }
        await expectLater(f.read(kind), throwsStateError);
      });
    }
    for (final change in ['sid', 'sid-aba', 'company', 'role', 'worker-status']) {
      test('$kind late $change cannot adopt an old result', () async {
        final f = await _Fixture.create(); addTearDown(f.close);
        f.waitPath = '/worker_qualifications'; f.wait = Completer<void>();
        final pending = f.read(kind); final rejected = expectLater(pending, throwsStateError);
        await f.started.future.timeout(const Duration(seconds: 5));
        switch (change) {
          case 'sid': await f.login(sessionId: sid2);
          case 'sid-aba': await f.login(sessionId: sid2); await f.login();
          case 'company': f.members.single['company_id'] = otherCompany;
          case 'role': f.members.single['role'] = 'admin';
          case 'worker-status': f.workers.single['status'] = 'active';
        }
        f.wait!.complete(); await rejected;
      });
    }
    for (final failure in ['error', 'done']) {
      test('$kind tracking $failure permanently rejects late data and fresh SID ABA', () async {
        final f = await _Fixture.create(); addTearDown(f.close);
        final events = StreamController<AuthState>.broadcast();
        addTearDown(() async { if (!events.isClosed) await events.close(); });
        f.client.observed = _ObservedAuth(f.client.originalAuth, events.stream);
        f.waitPath = '/worker_qualifications'; f.wait = Completer<void>();
        final pending = f.read(kind); final rejected = expectLater(pending, throwsStateError);
        await f.started.future.timeout(const Duration(seconds: 5));
        if (failure == 'error') { events.addError(StateError('synthetic observation failure')); } else { await events.close(); }
        await Future<void>.delayed(Duration.zero);
        await f.login(sessionId: sid2); await f.login(); f.wait!.complete(); await rejected;
        final before = f.requests.length;
        await expectLater(f.read(kind), throwsStateError); expect(f.requests.length, before);
      });
    }
    test('$kind photo signs only saved row using captured bearer and independent bucket headers', () async {
      final f = await _Fixture.create(); addTearDown(f.close);
      final auth = f.client.auth.currentSession;
      final before = Map.of(f.client.storage.from('qualification-certificates').headers);
      expect(await f.photo(kind, path), contains('token=signed'));
      expect(f.client.auth.currentSession, same(auth));
      expect(f.client.storage.from('qualification-certificates').headers, before);
      final sign = f.requests.singleWhere((r) => r.url.path.contains('/object/sign/'));
      expect(sign.headers['Authorization'], 'Bearer ${auth!.accessToken}');
      expect(f.requests.any((r) => r.url.path.endsWith('ensure_current_user_worker')), false);
    });
    for (final badPath in ['https://foreign.invalid/file.jpg', '$otherCompany/$worker/$qualification/front.jpg', '$company/$worker/$qualification/../front.jpg', '$company/$worker/$qualification/%2e%2e.jpg', '$company/$worker/$qualification/unknown.jpg']) {
      test('$kind malformed or unreferenced photo is never signed: $badPath', () async {
        final f = await _Fixture.create(); addTearDown(f.close);
        if (!badPath.endsWith('unknown.jpg')) f.qualifications.single['attachment_path'] = badPath;
        await expectLater(f.photo(kind, badPath), throwsStateError);
        expect(f.requests.any((r) => r.url.path.contains('/object/sign/')), false);
      });
    }
    test('$kind targeted photo lookup rejects another valid saved UUID', () async {
      final f = await _Fixture.create(); addTearDown(f.close);
      const legacy = '$company/$worker/front.jpg';
      f.qualifications.single['attachment_path'] = legacy;
      f.ignoreQualificationFilters = true;
      if (kind == 'cloud') {
        f.qualifications.single['id'] = '50000000-0000-0000-0000-000000000002';
        await expectLater(f.photo(kind, legacy), throwsStateError);
        expect(f.requests.any((r) => r.url.path.contains('/object/sign/')), false);
      } else {
        // Path-only manager/own API selects the original row; a changed UUID on
        // its post-sign targeted reload must never return the old signed URL.
        f.waitPath = '/object/sign/'; f.wait = Completer<void>();
        final pending = f.photo(kind, legacy); final rejected = expectLater(pending, throwsStateError);
        await f.started.future.timeout(const Duration(seconds: 5));
        f.qualifications.single['id'] = '50000000-0000-0000-0000-000000000002';
        f.wait!.complete(); await rejected;
      }
    });
    test('$kind photo changed during signing never returns the stale URL', () async {
      final f = await _Fixture.create(); addTearDown(f.close);
      f.waitPath = '/object/sign/'; f.wait = Completer<void>();
      final pending = f.photo(kind, path); final rejected = expectLater(pending, throwsStateError);
      await f.started.future.timeout(const Duration(seconds: 5));
      f.qualifications.single['attachment_path'] = '$company/$worker/$qualification/replaced.jpg';
      f.wait!.complete(); await rejected;
    });
    test('$kind confirmed extra-photo fallback retains the same captured bearer', () async {
      final f = await _Fixture.create(); addTearDown(f.close); f.missingExtras = true;
      expect((await f.read(kind))['qualifications'], hasLength(1));
      expect(f.qualificationReads, 2);
      expect(f.requests.every((r) => r.headers['Authorization'] == 'Bearer ${f.client.auth.currentSession!.accessToken}'), true);
    });
  }
  test('certificate manager may preview another authorized worker without broadening own preview', () async {
    final f = await _Fixture.create(); addTearDown(f.close);
    f.members.single['role'] = 'admin'; f.permissions = {'can_manage_people': true};
    f.workers.add({'id': otherWorker, 'company_id': company, 'user_id': otherActor, 'name': 'Other', 'status': 'inactive'});
    final otherPath = '$company/$otherWorker/$qualification/other.jpg';
    f.qualifications.single['worker_id'] = otherWorker; f.qualifications.single['attachment_path'] = otherPath;
    expect(await f.certificates.createSignedUrl(otherPath), contains('token=signed'));
    await expectLater(f.cloud.createOwnQualificationPhotoUrl(qualificationId: qualification, storagePath: otherPath), throwsStateError);
  });
  test('existing active registration and mutation routes retain their initializer and payload', () async {
    final f = await _Fixture.create(); addTearDown(f.close); f.workers.single['status'] = 'active';
    final result = await f.cloud.insertOwnQualification(qualificationMasterId: master, certificateNumber: 'ACTIVE');
    expect(result['worker_id'], worker);
    expect(f.requests.where((r) => r.url.path.endsWith('ensure_current_user_worker')), hasLength(1));
    final saved = f.requests.singleWhere((r) => r.url.path.endsWith('/worker_qualifications') && r.method == 'POST');
    expect((jsonDecode(saved.body) as Map)['worker_id'], worker);
    expect((jsonDecode(saved.body) as Map)['company_id'], company);
  });
  test('write/new-registration methods remain byte-identical and do not use the read-only scope', () {
    final source = File('lib/features/qualifications/qualification_cloud_repository.dart').readAsStringSync();
    final current = source.substring(source.indexOf('Future<({String workerId, String workerName})> currentWorker'), source.indexOf('String? get currentUserId'));
    expect(current, contains("rpc('ensure_current_user_worker')"));
    final write = source.substring(source.indexOf('Future<Map<String, dynamic>> insertOwnQualification'));
    expect(write, contains('await currentWorker()'));
    expect(write, isNot(contains('QualificationDocumentReadScope.capture')));
  });
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _company = '10000000-0000-0000-0000-000000000002';
const _worker = '10000000-0000-0000-0000-000000000003';
const _sidA = '10000000-0000-0000-0000-000000000004';
const _sidB = '10000000-0000-0000-0000-000000000005';
const _updated = '2026-10-29T00:00:00Z';
const _bank = {'worker_id': _worker, 'company_id': _company, 'updated_at': _updated};
const _requirements = [
  {'id': 'bank', 'name': '銀行口座情報', 'is_active': true, 'is_required': true, 'expiry_required': false},
  {'id': 'health', 'name': '健康診断書', 'is_active': true, 'is_required': true, 'expiry_required': true},
];
const _statuses = [
  {'id': 'synthetic-bank-status', 'worker_id': _worker, 'requirement_id': 'bank', 'status': 'submitted',
    'attachment_path': 'synthetic/metadata-is-not-account-evidence'},
  {'id': 'synthetic-health-status', 'worker_id': _worker, 'requirement_id': 'health', 'status': 'submitted',
    'attachment_path': 'synthetic/retained-object', 'expires_at': '2027-01-01'},
];
Map<String, dynamic> _documents({bool known = true, Object? metadata = _bank, bool exempt = false}) => {
  'company_id': _company, 'worker_id': _worker, 'requirements': _requirements, 'statuses': _statuses,
  'bank_account_known': known, 'bank_account_metadata': metadata,
  'exemptions': [if (exempt) {'worker_id': _worker, 'requirement_id': 'bank',
    'active': true, 'version': 1, 'reason': 'synthetic exemption'}],
};
TutorialEvidenceCheckpoint _bankCheckpoint(Map<String, dynamic> docs) =>
  TutorialEvidenceRepository.documentCheckpoints(docs, today: DateTime(2026, 10, 29))
    .singleWhere((item) => item.key == 'document:bank');

class _WireFixture {
  final requests = <http.Request>[];
  String sid = _sidA;
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  bool denyBank = false;
  Completer<void>? bankEntered, bankRelease;
  late final client = SupabaseClient('https://synthetic.invalid', 'synthetic-public',
    authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient(_respond));
  String token(String id) {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': _actor, 'session_id': id, 'exp': expiry})}.synthetic';
  }
  Future<void> login(String id) async {
    sid = id;
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic');
    await Future<void>.delayed(Duration.zero);
  }
  Future<http.Response> _respond(http.Request request) async {
    requests.add(request);
    Object? value;
    var status = 200;
    switch (request.url.path) {
      case '/auth/v1/token':
        value = {'access_token': token(sid), 'refresh_token': 'synthetic', 'expires_in': 3600,
          'token_type': 'bearer', 'user': {'id': _actor, 'aud': 'authenticated', 'role': 'authenticated',
            'email': 'synthetic@example.invalid', 'app_metadata': {}, 'user_metadata': {}, 'created_at': _updated}};
      case '/rest/v1/company_members': value = {'company_id': _company, 'role': 'employee'};
      case '/rest/v1/workers': value = {'id': _worker};
      case '/rest/v1/document_requirements': value = _requirements;
      case '/rest/v1/worker_document_statuses': value = _statuses;
      case '/rest/v1/rpc/worker_document_exemption': value = {'capability_version': 1, 'items': []};
      case '/rest/v1/worker_private_bank_accounts':
        bankEntered?.complete();
        if (bankRelease != null) { await bankRelease!.future; }
        if (denyBank) { status = 403; value = {'code': '42501', 'message': 'synthetic access denied'}; }
        else { value = _bank; }
      default: throw StateError('unexpected synthetic metadata endpoint');
    }
    return http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'}, request: request);
  }
  Future<TutorialEvidenceSnapshot> load() => TutorialEvidenceRepository.forClient(client, today: DateTime(2026, 10, 29))
      .load(availableActionKeys: const {'document_register'});
}

void main() {
  test('bank evidence uses exact scoped saved metadata, never document photo/status', () {
    final saved = _bankCheckpoint(_documents());
    expect(saved.state, TutorialEvidenceState.saved);
    expect(saved.evidenceKey, 'bank:$_worker:$_updated');
    expect(_bankCheckpoint(_documents(metadata: null)).state, TutorialEvidenceState.missing);
    for (final docs in [
      _documents(known: false), _documents(metadata: {..._bank, 'worker_id': 'another-worker'}),
      _documents(metadata: {..._bank, 'company_id': 'another-company'}),
      _documents(metadata: {..._bank, 'updated_at': 'invalid'}),
    ]) {
      final item = _bankCheckpoint(docs);
      expect(item.state, TutorialEvidenceState.unknown); expect(item.evidenceKey, isNull);
    }
    expect(_bankCheckpoint(_documents(metadata: null, exempt: true)).state, TutorialEvidenceState.notApplicable);
  });

  test('actual SDK metadata wire selects no bank contents and retains exact bearer/company/worker scope', () async {
    final fixture = _WireFixture(); addTearDown(fixture.client.dispose);
    await fixture.login(_sidA); fixture.requests.clear();
    final snapshot = await fixture.load();
    final items = snapshot.tasks.single.checkpoints;
    expect(items.singleWhere((item) => item.key == 'document:bank').state, TutorialEvidenceState.saved);
    expect(items.singleWhere((item) => item.key == 'document:health').state, TutorialEvidenceState.saved);
    expect(fixture.requests.map((r) => r.url.path), [
      '/rest/v1/company_members', '/rest/v1/workers', '/rest/v1/document_requirements',
      '/rest/v1/worker_document_statuses', '/rest/v1/rpc/worker_document_exemption', '/rest/v1/worker_private_bank_accounts',
    ]);
    for (final request in fixture.requests) { expect(request.headers['Authorization'], 'Bearer ${fixture.token(_sidA)}'); }
    final bank = fixture.requests.last;
    expect(bank.method, 'GET');
    expect(bank.url.queryParameters, {'select': 'worker_id,company_id,updated_at', 'worker_id': 'eq.$_worker', 'company_id': 'eq.$_company'});
    expect(fixture.requests.first.url.queryParameters['user_id'], 'eq.$_actor');
    expect(fixture.requests[1].url.queryParameters['user_id'], 'eq.$_actor');
    for (final request in fixture.requests.where((r) => r.url.path != '/rest/v1/company_members')) {
      if (!request.url.path.contains('/rpc/')) { expect(request.url.queryParameters['company_id'], 'eq.$_company'); }
    }
    expect(jsonDecode(fixture.requests[4].body), {'p_action': 'list', 'p_data': {'company_id': _company}});
  });

  test('bank RLS denial stays unknown without erasing valid health evidence', () async {
    final fixture = _WireFixture()..denyBank = true; addTearDown(fixture.client.dispose);
    await fixture.login(_sidA);
    final items = (await fixture.load()).tasks.single.checkpoints;
    expect(items.singleWhere((item) => item.key == 'document:bank').state, TutorialEvidenceState.unknown);
    expect(items.singleWhere((item) => item.key == 'document:health').state, TutorialEvidenceState.saved);
  });

  test('bank reply after same UID SID A B A never restores the stale snapshot', () async {
    final fixture = _WireFixture()..bankEntered = Completer<void>()..bankRelease = Completer<void>();
    addTearDown(fixture.client.dispose);
    await fixture.login(_sidA);
    final pending = fixture.load(); await fixture.bankEntered!.future;
    await fixture.login(_sidB); await fixture.login(_sidA);
    expect(fixture.client.auth.currentSession!.accessToken, fixture.token(_sidA));
    fixture.bankRelease!.complete();
    final items = (await pending).tasks.single.checkpoints;
    expect(items, isNotEmpty);
    expect(items.every((item) => item.state == TutorialEvidenceState.unknown), isTrue);
    expect(items.any((item) => item.state == TutorialEvidenceState.saved), isFalse);
    final bank = fixture.requests.singleWhere((r) => r.url.path.endsWith('/worker_private_bank_accounts'));
    expect(bank.headers['Authorization'], 'Bearer ${fixture.token(_sidA)}');
  });
}

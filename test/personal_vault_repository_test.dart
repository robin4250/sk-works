import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/personal_vault/personal_vault_page.dart';
import 'package:sk_works/features/personal_vault/personal_vault_repository.dart';
void main() {
 final row = {'manifest_id':'10000000-0000-0000-0000-000000000001',
  'artifact_key':'a'*64,'kind':'own_attendance',
  'source_company_id':'20000000-0000-0000-0000-000000000001',
  'completed_at':'2026-10-27T00:00:00Z'};
 test('completed receipt list parses and malformed/duplicate responses fail closed', () {
  expect(PersonalVaultRepository.parseMine([row]).single.label,'本人出勤表');
  expect(()=>PersonalVaultRepository.parseMine([row,row]),throwsFormatException);
  expect(()=>PersonalVaultRepository.parseMine([{
   ...row,'kind':'company_internal'}]),throwsFormatException);
  expect(()=>PersonalVaultRepository.parseMine(null),throwsFormatException);
 });
 group('read session history', () {
  const actor = '30000000-0000-0000-0000-000000000001';
  const other = '30000000-0000-0000-0000-000000000002';
  late SupabaseClient client;
  late StreamController<AuthState> events;
  late List<String> paths;
  late List<String?> authorizations;
  late String emitAt;
  late void Function() emit;
  final pdf = utf8.encode('%PDF-1.7\nfixture only');
  Map<String, dynamic> session(String id, String marker) {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return {'access_token': '${part({'alg':'HS256'})}.${part({'sub':id,'exp':4102444800})}.$marker',
      'refresh_token':'synthetic-refresh', 'token_type':'bearer', 'expires_in':3600,
      'user': {'id':id,'aud':'authenticated','created_at':'2026-01-01T00:00:00Z',
        'app_metadata':{},'user_metadata':{}}};
  }
  Session authSession(String id, String marker) => Session.fromJson(session(id, marker))!;
  void history(Session changed) {
    events.add(AuthState(AuthChangeEvent.signedIn, changed));
    events.add(AuthState(AuthChangeEvent.signedIn, client.auth.currentSession));
  }
  setUp(() async {
    events = StreamController<AuthState>.broadcast(); paths = []; authorizations = [];
    emitAt = ''; emit = () {};
    client = SupabaseClient('https://vault-fixture.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken:false),
      httpClient: MockClient((request) async {
        paths.add(request.url.path); authorizations.add(request.headers['Authorization']);
        if (request.url.path.contains(emitAt) && emitAt.isNotEmpty) { emit(); }
        if (request.url.path.contains('/storage/')) {
          return http.Response.bytes(pdf, 200, headers:{'content-type':'application/pdf'});
        }
        final result = request.url.path.endsWith('personal_vault24_list_mine') ? [row] : [{
          'object_path':'personal-vault/$actor/${'a'*64}.pdf',
          'object_version':'fixture-version', 'pdf_hash':sha256.convert(pdf).toString(),
          'byte_length':pdf.length}];
        return http.Response(jsonEncode(result), 200, headers:{'content-type':'application/json'});
      }));
    await client.auth.setInitialSession(jsonEncode(session(actor, 'original')));
  });
  tearDown(() async { await events.close(); await client.dispose(); });
  PersonalVaultRepository repository() => PersonalVaultRepository(client, authChanges:events.stream);
  const entry = PersonalVaultEntry(
    id:'10000000-0000-0000-0000-000000000001:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    label:'本人出勤表',sourceCompanyLabel:'元会社',periodLabel:'保管済み');
  test('same session returns own list and hash-verified bytes with exact RPC bearer', () async {
    expect(await repository().loadMine(), hasLength(1));
    expect(await repository().downloadMine(entry), pdf);
    expect(authorizations.take(2), everyElement('Bearer ${client.auth.currentSession!.accessToken}'));
    expect(events.hasListener, isFalse);
  });
  test('queued A to B to A rejects list despite unchanged current session', () async {
    emitAt = 'personal_vault24_list_mine'; emit = () => history(authSession(other, 'foreign'));
    await expectLater(repository().loadMine(), throwsStateError);
    expect(client.auth.currentUser!.id, actor); expect(events.hasListener, isFalse);
  });
  test('same UID token switch and return rejects metadata before Storage', () async {
    emitAt = 'personal_vault24_item_mine'; emit = () => history(authSession(actor, 'replaced'));
    await expectLater(repository().downloadMine(entry), throwsStateError);
    expect(paths.any((path) => path.contains('/storage/')), isFalse);
    expect(events.hasListener, isFalse);
  });
  test('queued account switch during Storage never returns downloaded bytes', () async {
    emitAt = '/storage/'; emit = () => history(authSession(other, 'foreign'));
    await expectLater(repository().downloadMine(entry), throwsStateError);
    expect(paths.any((path) => path.contains('/storage/')), isTrue);
    expect(events.hasListener, isFalse);
  });
  test('signout history rejects list after a same-token event', () async {
    emitAt = 'personal_vault24_list_mine'; emit = () {
      events.add(const AuthState(AuthChangeEvent.signedOut, null));
      events.add(AuthState(AuthChangeEvent.signedIn, client.auth.currentSession));
    };
    await expectLater(repository().loadMine(), throwsStateError);
    expect(events.hasListener, isFalse);
  });
  test('Auth stream failure rejects list and releases subscription', () async {
    emitAt = 'personal_vault24_list_mine'; emit = () => events.addError(StateError('fixture error'));
    await expectLater(repository().loadMine(), throwsStateError);
    expect(events.hasListener, isFalse);
  });
  test('closed Auth history rejects an in-flight list', () async {
    emitAt = 'personal_vault24_list_mine'; emit = () { unawaited(events.close()); };
    await expectLater(repository().loadMine(), throwsStateError);
    expect(events.hasListener, isFalse);
  });
 });
}

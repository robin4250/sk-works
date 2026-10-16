import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/master_credential_repository.dart';
const _actor = '50000000-0000-0000-0000-000000000001';
const _sid = '50000000-0000-0000-0000-000000000002';
const _request = '50000000-0000-0000-0000-000000000003';
const _challenge = '50000000-0000-0000-0000-000000000004';
const _device = 'synthetic-device-key-longer-than-32';
const _protocol = 'sko-master-password-v1';
Map<String, dynamic> _session() {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return {'access_token': '${part({'alg':'HS256'})}.${part({'sub':_actor,'session_id':_sid,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch ~/ 1000+3600})}.synthetic', 'refresh_token':'synthetic', 'token_type':'bearer','expires_in':3600, 'user':{'id':_actor,'aud':'authenticated','created_at':'2026-10-16T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
Map<String, dynamic> _applied() => {'protocol':_protocol,'status':'applied','operation':'setup','request_id':_request,'credential_version':1,'configured':true};
class _Wire {
  _Wire() {
    client = SupabaseClient('https://master-credential-fixture.invalid','public_fixture',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
      expect(r.url.host,'master-credential-fixture.invalid'); calls.add(r);
      final name = r.url.path.split('/').last;
      dynamic value;
      if (name == 'master_password_capability') { value = {'protocol':_protocol,'enabled':enabled}; }
      else if (name == 'current_master_password_status') { value = {'protocol':_protocol,'status':denied ? 'denied':'ready',if (!denied) 'configured':false,if (!denied) 'credential_version':0}; }
      else if (name == 'begin_master_password_operation') { value = {'protocol':_protocol,'status':'challenge','operation':'setup','expected_version':0,'request_id':_request,'challenge_id':_challenge,'nonce':List.filled(64,'a').join(),'expires_at':DateTime.now().toUtc().add(const Duration(seconds:120)).toIso8601String()}; }
      else if (name == 'complete_master_password_operation') { value = malformed ? {..._applied(),'credential_version':2} : _applied(); }
      else if (name == 'read_master_password_request') { value = {'protocol':_protocol,'status':found ? 'found':'not_found','request_id':_request,if(found) 'result':_applied()}; }
      else { throw StateError('Unexpected fixture request'); }
      return http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'},request:r);
    }));
    repository = MasterCredentialRepository(client,deviceKey:_device);
  }
  late final SupabaseClient client;
  late final MasterCredentialRepository repository;
  bool enabled = true, denied = false, malformed = false, found = false;
  final calls = <http.Request>[];
  Future<void> start() => client.auth.setInitialSession(jsonEncode(_session()));
  MasterCredentialPending pending() => MasterCredentialPending(actor:_actor,sessionId:_sid,deviceFingerprint:repository.binding!.deviceFingerprint,requestId:_request,operation:'setup',version:0);
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('default OFF and denied status cannot expose a credential form contract', () async {
    final w = _Wire(); await w.start(); w.enabled = false;
    await expectLater(w.repository.read(w.repository.binding!),throwsA(isA<MasterCredentialRejected>()));
    expect(w.calls.length,1); w.enabled = true; w.denied = true;
    await expectLater(w.repository.read(w.repository.binding!),throwsA(isA<MasterCredentialRejected>()));
    await w.client.dispose();
  });
  test('actual pinned SDK uses only new RPCs and captured bearer with exact contract', () async {
    final w = _Wire(); await w.start(); final binding = w.repository.binding!;
    final status = await w.repository.read(binding); expect(status.configured,false);
    final pending = w.pending(); final challenge = await w.repository.begin(binding,pending);
    await w.repository.commit(binding,pending,challenge,verificationPassword:'synthetic-secondary',newPassword:'synthetic-new-master');
    final call = w.calls.last; expect(call.url.path,'/rest/v1/rpc/complete_master_password_operation');
    expect(call.headers['Authorization'],'Bearer ${binding.token}');
    expect(jsonDecode(call.body),{'p_device_key':_device,'p_challenge_id':_challenge,'p_nonce':List.filled(64,'a').join(),'p_existing_password':'synthetic-secondary','p_new_password':'synthetic-new-master','p_request_id':_request});
    expect(w.calls.where((r)=>r.url.path.contains('secondary_password')||r.url.path.endsWith('/user')||r.url.path.endsWith('/signup')),isEmpty);
    await w.client.dispose();
  });
  test('malformed successful response is unknown; receipt sends no passwords or nonce', () async {
    final w = _Wire(); await w.start(); final binding = w.repository.binding!; final pending = w.pending();
    final challenge = await w.repository.begin(binding,pending); w.malformed = true;
    await expectLater(w.repository.commit(binding,pending,challenge,verificationPassword:'synthetic-secondary',newPassword:'synthetic-master'),throwsA(isA<FormatException>()));
    expect(await w.repository.receipt(binding,pending),false); w.found = true;
    expect(await w.repository.receipt(binding,pending),true);
    expect(jsonDecode(w.calls.last.body),{'p_device_key':_device,'p_request_id':_request});
    await w.client.dispose();
  });
  test('journal corruption and device changes fail closed; other sessions cannot read it', () async {
    final w = _Wire(); await w.start(); final binding = w.repository.binding!, pending = w.pending();
    await w.repository.remember(pending);
    final otherSession = MasterCredentialBinding(binding.actor, 'other-session', binding.token, binding.deviceKey);
    expect(await w.repository.pending(otherSession), isNull);
    final otherDevice = MasterCredentialBinding(binding.actor, binding.sessionId, binding.token, 'different-device-key-longer-than-32');
    await expectLater(w.repository.pending(otherDevice), throwsA(isA<FormatException>()));
    final prefs = await SharedPreferences.getInstance(); await prefs.setString(prefs.getKeys().single, '{');
    await expectLater(w.repository.pending(binding), throwsA(isA<FormatException>()));
    await w.client.dispose();
  });
  test('durable metadata restores the same session and refuses conflicting requests', () async {
    final w = _Wire(); await w.start(); final binding = w.repository.binding!, pending = w.pending();
    await w.repository.remember(pending); expect((await w.repository.pending(binding))!.requestId,_request);
    expect(pending.toJson().keys.toSet(),{'actor','session_id','device_fingerprint','request_id','operation','version'});
    final other = MasterCredentialPending(actor:_actor,sessionId:_sid,deviceFingerprint:binding.deviceFingerprint,requestId:newMasterCredentialRequestId(),operation:'setup',version:0);
    await expectLater(w.repository.remember(other),throwsStateError);
    await w.repository.forget(other); // Another UUID must not delete this request.
    final fresh = MasterCredentialRepository(w.client,deviceKey:_device); expect((await fresh.pending(binding))!.requestId,_request);
    final prefs = await SharedPreferences.getInstance(); final stored = prefs.getString(prefs.getKeys().single)!;
    expect(stored, isNot(contains(binding.token))); expect(stored, isNot(contains(_device)));
    await w.repository.forget(pending); expect(await fresh.pending(binding),isNull);
    await w.client.dispose();
  });
}

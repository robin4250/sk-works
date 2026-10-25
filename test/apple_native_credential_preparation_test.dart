import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/apple_native_credential_preparation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '40000000-0000-0000-0000-000000000001';
const other = '40000000-0000-0000-0000-000000000002';
Map<String, dynamic> user(String id, {bool google = true}) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': {}, 'user_metadata': {}, 'identities': [if (google)
    {'id': 'google-$id', 'identity_id': id, 'user_id': id, 'provider': 'google',
      'identity_data': {'sub': 'google-$id'}, 'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z'}],
};
String session(String id, {int variant = 0}) {
  String part(Object x) => base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=', '');
  return jsonEncode({'access_token': '${part({'alg':'HS256'})}.${part({
    'sub': id, 'session_id': 'synthetic-$variant', 'exp': 4102444800})}.synthetic',
    'refresh_token':'synthetic', 'token_type':'bearer', 'expires_in':3600, 'user': user(id)});
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.skworks.sko/apple_credential');
  late SupabaseClient client;
  late StreamController<AuthState> changes;
  late List<http.Request> network;
  bool google = true;
  int calls = 0;
  Future<Object?> Function()? native;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    changes = StreamController<AuthState>.broadcast(); network = []; google = true; calls = 0;
    native = () async => {'id_token':'header.payload.signature', 'nonce':'n' * 43};
    client = SupabaseClient('https://native-apple.invalid','synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        network.add(r);
        if (r.method != 'GET' || !r.url.path.endsWith('/user')) throw StateError('auth mutation forbidden');
        return http.Response(jsonEncode(user(actor, google: google)),200,headers:{'content-type':'application/json'});
      }));
    await client.auth.setInitialSession(session(actor));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      expect(call.method,'requestAppleCredential'); expect(call.arguments,isNull); calls++; return native!();
    });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    await changes.close(); await client.dispose(); debugDefaultTargetPlatformOverride = null;
  });
  AppleNativeCredentialPreparation preparation({bool enabled = true}) =>
    AppleNativeCredentialPreparation(client,enabled: enabled,channel: channel,authChanges: changes.stream);
  void unchanged(String token) {
    expect(client.auth.currentUser!.id,actor); expect(client.auth.currentSession!.accessToken,token);
    expect(network.every((r) => r.method == 'GET'),isTrue);
  }
  test('default OFF performs no native or network operation',() async {
    final source = AppleNativeCredentialPreparation(client);
    await expectLater(source.requestForExistingGoogleAccount(),throwsStateError);
    expect(calls,0); expect(network,isEmpty);
  });
  test('captures credential only after server confirms exact existing Google user',() async {
    final token = client.auth.currentSession!.accessToken;
    final value = await preparation().requestForExistingGoogleAccount();
    expect(value.actorId,actor); expect(value.exactAccessToken,token); expect(value.nonce,'n' * 43);
    expect(calls,1); unchanged(token);
  });
  test('server without Google identity cannot launch native request',() async {
    google = false;
    await expectLater(preparation().requestForExistingGoogleAccount(),throwsStateError);
    expect(calls,0);
  });
  test('historical A to B to A event permanently invalidates pending credential',() async {
    final original = client.auth.currentSession!;
    native = () async {
      final b = Session.fromJson(jsonDecode(session(other)) as Map<String,dynamic>)!;
      changes.add(AuthState(AuthChangeEvent.signedIn,b));
      changes.add(AuthState(AuthChangeEvent.signedIn,original));
      return {'id_token':'header.payload.signature', 'nonce':'n' * 43};
    };
    await expectLater(preparation().requestForExistingGoogleAccount(),throwsStateError);
    unchanged(original.accessToken);
  });
  test('historical same actor token switch invalidates pending credential',() async {
    final original = client.auth.currentSession!;
    native = () async {
      final next = Session.fromJson(jsonDecode(session(actor,variant:1)) as Map<String,dynamic>)!;
      changes.add(AuthState(AuthChangeEvent.tokenRefreshed,next));
      changes.add(AuthState(AuthChangeEvent.tokenRefreshed,original));
      return {'id_token':'header.payload.signature', 'nonce':'n' * 43};
    };
    await expectLater(preparation().requestForExistingGoogleAccount(),throwsStateError);
    unchanged(original.accessToken);
  });
  test('malformed payload and native errors cannot return a credential',() async {
    for (final value in [null, {'id_token':'header.payload.signature','nonce':'short'},
      {'id_token':'header.payload.signature','nonce':'n' * 43,'actor_id':other}]) {
      native = () async => value;
      await expectLater(preparation().requestForExistingGoogleAccount(),throwsStateError);
    }
    native = () async => throw PlatformException(code:'cancelled');
    await expectLater(preparation().requestForExistingGoogleAccount(),throwsStateError);
  });
  test('unsupported platform remains preparation only without server/native calls',() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(preparation().requestForExistingGoogleAccount(),throwsStateError);
    expect(calls,0); expect(network,isEmpty);
  });
}

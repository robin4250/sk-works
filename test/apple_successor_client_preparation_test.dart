import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/apple_successor_client_preparation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '40000000-0000-0000-0000-000000000001';
const other = '40000000-0000-0000-0000-000000000002';
const requestId = '40000000-0000-0000-0000-000000000003';
const originalSid = '40000000-0000-0000-0000-000000000004';
const successorSid = '40000000-0000-0000-0000-000000000005';
const origin = 'https://successor-fixture.invalid';

Map<String, dynamic> user(String id, {bool apple = false, String? googleId}) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': {}, 'user_metadata': {}, 'identities': [
    {'id': googleId ?? 'google-$id', 'identity_id': id, 'user_id': id, 'provider': 'google',
      'identity_data': {'sub': 'google-$id'}, 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z'},
    if (apple) {'id': 'apple-$id', 'identity_id': requestId, 'user_id': id, 'provider': 'apple',
      'identity_data': {'sub': 'synthetic-apple'}, 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z'},
  ],
};
String token(String id, String sid, {int expires = 4102444800}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': id, 'session_id': sid, 'exp': expires, 'iat': 1767225600,
    'iss': '$origin/auth/v1', 'aud': 'authenticated'})}.${base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '')}';
}
String initialSession(String id) => jsonEncode({'access_token': token(id, originalSid),
  'refresh_token': 'synthetic-original', 'token_type': 'bearer', 'expires_in': 3600, 'user': user(id)});
Map<String, dynamic> envelope() => {'schema': 1, 'request_id': requestId, 'user_id': actor,
  'session_id': successorSid, 'token_type': 'bearer', 'access_token': token(actor, successorSid),
  'refresh_token': 'synthetic-successor'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient application;
  late StreamController<AuthState> changes;
  late List<http.Request> applicationRequests, isolatedRequests;
  late List<AppleSuccessorClientPreparation> preparations;
  late List<Map<String, dynamic>> companies;
  late Map<String, dynamic> isolatedUser;
  int isolatedCreations = 0;
  Future<void> Function()? isolatedBeforeUser;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    applicationRequests = []; isolatedRequests = []; preparations = [];
    companies = [{'company_id': requestId, 'role': 'owner'}];
    isolatedUser = user(actor, apple: true); isolatedCreations = 0; isolatedBeforeUser = null;
    changes = StreamController<AuthState>.broadcast();
    application = SupabaseClient(origin, 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
        applicationRequests.add(request);
        if (request.method != 'GET') { throw StateError('application auth mutation forbidden'); }
        final value = request.url.path.endsWith('/user') ? user(actor) : [{'company_id': requestId, 'role': 'owner'}];
        return http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    await application.auth.setInitialSession(initialSession(actor));
  });
  tearDown(() async {
    for (final preparation in preparations) { await preparation.dispose(); }
    await changes.close(); await application.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  AppleSuccessorClientPreparation make({bool? enabled}) {
    SupabaseClient factory() {
      isolatedCreations++;
      return SupabaseClient(origin, 'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
          isolatedRequests.add(request);
          if (request.method != 'GET') { throw StateError('refresh exchange forbidden for this fresh-token fixture'); }
          if (request.url.path.endsWith('/user')) {
            await isolatedBeforeUser?.call();
            return http.Response(jsonEncode(isolatedUser), 200, headers: {'content-type': 'application/json'}, request: request);
          }
          return http.Response(jsonEncode(companies), 200, headers: {'content-type': 'application/json'}, request: request);
        }));
    }
    final preparation = enabled == null
      ? AppleSuccessorClientPreparation(application, projectUrl: origin, publicKey: 'synthetic-public',
          isolatedClientFactory: factory, authChanges: changes.stream)
      : AppleSuccessorClientPreparation(application, projectUrl: origin, publicKey: 'synthetic-public', enabled: enabled,
          isolatedClientFactory: factory, authChanges: changes.stream);
    preparations.add(preparation);return preparation;
  }
  void unchanged() {
    expect(application.auth.currentUser!.id, actor);
    expect(application.auth.currentSession!.accessToken, token(actor, originalSid));
    expect(application.auth.currentSession!.refreshToken, 'synthetic-original');
    expect(applicationRequests.every((request) => request.method == 'GET'), isTrue);
  }

  test('default OFF does not receive credentials, create isolated client, or touch network', () async {
    var received = false;
    await expectLater(make().prepare(requestId: requestId, receiveOnce: () async {received = true;return envelope();}), throwsStateError);
    expect(received, isFalse);expect(isolatedCreations, 0);expect(applicationRequests, isEmpty);unchanged();
  });
  test('SDK verifies same UID, Google identities and companies in memory without global adoption', () async {
    final preparation = make(enabled: true);
    await preparation.prepare(requestId: requestId, receiveOnce: () async => envelope());
    expect(preparation.ready, isTrue);expect(isolatedCreations, 1);
    expect(isolatedRequests.where((request) => request.url.path.endsWith('/user')).length, 1);
    expect(isolatedRequests.every((request) => request.method == 'GET'), isTrue);unchanged();
    preparation.invalidate();expect(preparation.ready, isFalse);
  });
  test('separate preparations cannot concurrently receive for one application client', () async {
    final received = Completer<void>(), delivered = Completer<Map<String, dynamic>>();
    var calls = 0;
    final first = make(enabled: true), second = make(enabled: true);
    final result = first.prepare(requestId: requestId, receiveOnce: () async {
      calls++; received.complete(); return delivered.future;
    });
    await received.future;
    await expectLater(second.prepare(requestId: requestId, receiveOnce: () async {
      calls++; return envelope();
    }), throwsStateError);
    // Disposing the rejected instance must not release the active owner's lease.
    await second.dispose();
    await expectLater(make(enabled: true).prepare(requestId: requestId, receiveOnce: () async {
      calls++; return envelope();
    }), throwsStateError);
    delivered.complete(envelope());
    await result;
    expect(first.ready, isTrue); expect(calls, 1); expect(isolatedCreations, 1);
    unchanged();
  });
  test('foreign request, actor and near-expiry envelope are refused before isolated SDK mutation', () async {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (value) => value['request_id'] = other,
      (value) => value['user_id'] = other,
      (value) => value['access_token'] = token(actor, successorSid, expires: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30),
    ]) {
      final value = envelope();mutate(value);
      await expectLater(make(enabled: true).prepare(requestId: requestId, receiveOnce: () async => value), throwsStateError);
    }
    expect(isolatedCreations, 0);unchanged();
  });
  test('original session cannot be passed off as an Apple successor', () async {
    final value = envelope()
      ..['session_id'] = originalSid
      ..['access_token'] = token(actor, originalSid);
    await expectLater(
      make(enabled: true).prepare(requestId: requestId, receiveOnce: () async => value),
      throwsStateError,
    );
    expect(isolatedCreations, 0);
    unchanged();
  });
  test('server Auth user or Google identity mismatch never changes application session', () async {
    for (final value in [user(other, apple: true), user(actor, apple: true, googleId: 'replaced-google')]) {
      isolatedUser = value;
      await expectLater(make(enabled: true).prepare(requestId: requestId, receiveOnce: () async => envelope()), throwsStateError);
      unchanged();
    }
  });
  test('company change and missing Apple identity are refused', () async {
    companies = [{'company_id': other, 'role': 'owner'}];
    await expectLater(make(enabled: true).prepare(requestId: requestId, receiveOnce: () async => envelope()), throwsStateError);
    companies = [{'company_id': requestId, 'role': 'owner'}];isolatedUser = user(actor);
    await expectLater(make(enabled: true).prepare(requestId: requestId, receiveOnce: () async => envelope()), throwsStateError);
    unchanged();
  });
  test('A to B to A auth history invalidates an in-flight response', () async {
    final preparation = make(enabled: true), original = application.auth.currentSession!;
    await expectLater(preparation.prepare(requestId: requestId, receiveOnce: () async {
      changes.add(AuthState(AuthChangeEvent.signedIn, Session.fromJson(jsonDecode(initialSession(other)))!));
      changes.add(AuthState(AuthChangeEvent.signedIn, original));return envelope();
    }), throwsStateError);
    expect(preparation.ready, isFalse);expect(isolatedCreations, 0);unchanged();
  });
  test('backgrounding during SDK getUser rejects late preparation without global session write', () async {
    final preparation = make(enabled: true);
    isolatedBeforeUser = () async {preparation.didChangeAppLifecycleState(AppLifecycleState.paused);};
    await expectLater(preparation.prepare(requestId: requestId, receiveOnce: () async => envelope()), throwsStateError);
    expect(preparation.ready, isFalse);unchanged();
  });
  test('readiness rejects a silent same-UID SDK session replacement', () async {
    final preparation = make(enabled: true);
    await preparation.prepare(requestId: requestId, receiveOnce: () async => envelope());
    expect(preparation.ready, isTrue);
    final original = application.auth.currentSession!.toJson();
    // Deliberately do not publish an event to changes: the getter must verify
    // the application's current SDK state independently of this stream.
    final changed = Map<String, dynamic>.from(original)
      ..['access_token'] = token(actor, successorSid)
      ..['refresh_token'] = 'synthetic-replacement';
    await application.auth.setInitialSession(jsonEncode(changed));
    expect(preparation.ready, isFalse);
    await application.auth.setInitialSession(jsonEncode(original));
    expect(preparation.ready, isFalse); // observed invalidation is terminal
  });
  test('readiness rejects a silently restored expired application token', () async {
    final preparation = make(enabled: true);
    await preparation.prepare(requestId: requestId, receiveOnce: () async => envelope());
    final expired = application.auth.currentSession!.toJson()
      ..['access_token'] = token(actor, originalSid, expires: 1);
    await application.auth.setInitialSession(jsonEncode(expired));
    expect(preparation.ready, isFalse);
  });
  test('unknown receive result has generic error and no automatic or manual retry in same operation', () async {
    final preparation = make(enabled: true);var calls = 0;
    try {
      await preparation.prepare(requestId: requestId, receiveOnce: () async {calls++;throw StateError('synthetic-successor-secret');});
      fail('expected unavailable');
    } catch (error) {expect(error.toString(), isNot(contains('synthetic-successor-secret')));}
    await expectLater(preparation.prepare(requestId: requestId, receiveOnce: () async {calls++;return envelope();}), throwsStateError);
    expect(calls, 1);unchanged();
  });
}


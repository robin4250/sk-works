// Fixed SDK + real loopback HTTP only. No live Auth, provider, server or Storage.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:sk_works/features/qualifications/admin_saved_qualification_photo_submission_repository.dart';
import 'package:sk_works/features/qualifications/qualification_photo_session_rpc_supabase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '00000000-0000-0000-0000-000000000002';
const target = '00000000-0000-0000-0000-000000000003';
const requestId = '00000000-0000-0000-0000-000000000004';
const other = '00000000-0000-0000-0000-000000000005';

class _RealHttpOverrides extends HttpOverrides {}

/// Even an unexpected SDK request cannot leave this one synthetic server.
class _LoopbackOnlyClient extends http.BaseClient {
  _LoopbackOnlyClient(this.port)
    : _inner = IOClient(_RealHttpOverrides().createHttpClient(null));
  final int port;
  final IOClient _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.scheme != 'http' ||
        request.url.host != '127.0.0.1' ||
        request.url.port != port) {
      throw StateError(
        'Only the isolated qualification HTTP fixture is allowed',
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

String _token(int revision, {String user = actor}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'sub': user, 'role': 'authenticated', 'exp': now + 3600, 'iat': now, 'fixture_revision': revision})}.synthetic';
}

String _session(String token, {String user = actor}) => jsonEncode({
  'access_token': token,
  'refresh_token': 'synthetic-not-used',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': user,
    'aud': 'authenticated',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': {'provider': 'google'},
    'user_metadata': <String, dynamic>{},
  },
});
AdminSavedQualificationPhotoSubmissionScope _scope({
  String selectedCompany = company,
}) => AdminSavedQualificationPhotoSubmissionScope(
  actorId: actor,
  companyId: selectedCompany,
  targetId: target,
  active: true,
);

class _Fixture {
  late final HttpServer server;
  late final SupabaseClient client;
  late final QualificationPhotoSessionRpcSupabase adapter;
  late final String originalToken;
  final contexts =
      StreamController<AdminSavedQualificationPhotoSubmissionScope>.broadcast(
        sync: true,
      );
  final lifecycle = StreamController<bool>.broadcast(sync: true);
  AdminSavedQualificationPhotoSubmissionScope context = _scope();
  bool foreground = true;
  final requests =
      <({String action, String? authorization, Map<String, dynamic> data})>[];
  Completer<void>? holdReadiness, readinessArrived;
  String receiptTarget = target;
  Object? serverError;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        if (request.method != 'POST' ||
            request.uri.path !=
                '/rest/v1/rpc/personal_qualification_submission') {
          throw StateError('Unexpected isolated SDK request');
        }
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final action = body['p_action'] as String;
        final data = Map<String, dynamic>.from(body['p_data'] as Map);
        requests.add((
          action: action,
          authorization: request.headers.value(HttpHeaders.authorizationHeader),
          data: data,
        ));
        Object result;
        if (action == 'admin_saved_photo_capability') {
          result = {
            'version': 1,
            'contract': 'qualification_admin_saved_photos',
            'company_id': company,
            'actor_id': actor,
            'photo_submission_available': true,
            'photo_upload_allowed': false,
            'max_photos': 20,
            'self_approval_allowed': false,
          };
        } else if (action == 'admin_saved_photo_prepare_readiness') {
          readinessArrived?.complete();
          await holdReadiness?.future;
          result = {
            'version': 1,
            'contract': 'qualification_admin_photo_prepare_baseline',
            'company_id': company,
            'actor_id': actor,
            'baseline_guard_version': 1,
            'prepare_action': 'prepare_admin_saved_photos',
            'photo_submission_available': true,
            'photo_upload_allowed': false,
            'max_photos': 20,
            'self_approval_allowed': false,
          };
        } else {
          result = {
            'version': 1,
            'id': requestId,
            'target_id': receiptTarget,
            'requested_by': actor,
            'status': 'draft',
            'cancelled': false,
            'reason': null,
            'photo_paths': <String>[],
            'upload_paths': <String>[],
          };
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
      } catch (error) {
        serverError = error;
        request.response.statusCode = 500;
        await request.response.close();
      }
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: _LoopbackOnlyClient(server.port),
    );
    originalToken = _token(1);
    await client.auth.setInitialSession(_session(originalToken));
    adapter = QualificationPhotoSessionRpcSupabase(
      client: client,
      scope: () => context,
      scopeChanges: contexts.stream,
      foreground: () => foreground,
      foregroundChanges: lifecycle.stream,
      enabled: true,
    );
  }

  Future<void> close() async {
    if (holdReadiness != null && !holdReadiness!.isCompleted)
      holdReadiness!.complete();
    await adapter.dispose();
    await contexts.close();
    await lifecycle.close();
    await client.dispose();
    await server.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Fixture fixture;
  setUp(() async {
    fixture = _Fixture();
    await fixture.start();
  });
  tearDown(() async {
    await fixture.close();
  });

  test('actual SDK sends captured Authorization to one RPC and returns scoped receipt', () async {
    final result = await fixture.adapter.rpc('get_photos', {'id': requestId});
    expect((result as Map)['target_id'], target);
    expect(fixture.requests.map((r) => r.action), [
      'admin_saved_photo_capability',
      'admin_saved_photo_prepare_readiness',
      'get_photos',
    ]);
    expect(
      fixture.requests.every(
        (r) => r.authorization == 'Bearer ${fixture.originalToken}',
      ),
      isTrue,
    );
    expect(fixture.requests.first.data, {'company_id': company});
    expect(fixture.requests.last.data, {'id': requestId});
    expect(fixture.serverError, isNull);
    await fixture.client.auth.setInitialSession(_session(_token(2)));
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      fixture.adapter.rpc('submit', {'id': requestId}),
      throwsStateError,
    );
    expect(fixture.requests.length, 3);
  });

  test('token change while real HTTP readiness is delayed rejects old response without write', () async {
    fixture.holdReadiness = Completer<void>();
    fixture.readinessArrived = Completer<void>();
    final operation = fixture.adapter.rpc('prepare_admin_saved_photos', {
      'company_id': company,
      'target_id': target,
      'request_id': requestId,
      'expected_photo_paths': ['fixture.jpg'],
      'photo_slots': <Object>[],
    });
    final rejected = expectLater(operation, throwsStateError);
    await fixture.readinessArrived!.future.timeout(const Duration(seconds: 10));
    await fixture.client.auth.setInitialSession(_session(_token(2)));
    fixture.holdReadiness!.complete();
    await rejected;
    expect(fixture.requests.map((r) => r.action), [
      'admin_saved_photo_capability',
      'admin_saved_photo_prepare_readiness',
    ]);
    expect(
      fixture.requests.every(
        (r) => r.authorization == 'Bearer ${fixture.originalToken}',
      ),
      isTrue,
    );
    expect(fixture.serverError, isNull);
  });

  test(
    'SDK wrapper retains background and company ABA invalidation before HTTP',
    () async {
      fixture.foreground = false;
      fixture.lifecycle.add(false);
      fixture.foreground = true;
      fixture.lifecycle.add(true);
      await expectLater(fixture.adapter.authorization(), throwsStateError);
      expect(fixture.requests, isEmpty);
      await fixture.adapter.dispose();
      fixture.adapter = QualificationPhotoSessionRpcSupabase(
        client: fixture.client,
        scope: () => fixture.context,
        scopeChanges: fixture.contexts.stream,
        foreground: () => fixture.foreground,
        foregroundChanges: fixture.lifecycle.stream,
        enabled: true,
      );
      fixture.context = _scope(selectedCompany: other);
      fixture.contexts.add(fixture.context);
      fixture.context = _scope();
      fixture.contexts.add(fixture.context);
      await expectLater(fixture.adapter.authorization(), throwsStateError);
      expect(fixture.requests, isEmpty);
    },
  );

  test('real SDK foreign receipt cannot reach submit or cancel RPC', () async {
    fixture.receiptTarget = other;
    await expectLater(
      fixture.adapter.rpc('cancel_photos', {'id': requestId}),
      throwsStateError,
    );
    expect(fixture.requests.map((r) => r.action), [
      'admin_saved_photo_capability',
      'admin_saved_photo_prepare_readiness',
      'get_photos',
    ]);
    expect(fixture.serverError, isNull);
  });
}

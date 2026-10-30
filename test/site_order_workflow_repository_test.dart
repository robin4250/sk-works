import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const sid = '20000000-0000-0000-0000-000000000001';
const package = '30000000-0000-0000-0000-000000000001';

class _Wire extends http.BaseClient {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String role = 'manager';
  int functionStatus = 200;
  bool malformedSuccess = false;
  int functions = 0;
  String? authorization;
  Completer<void>? hold;
  Completer<void>? started;
  String token() {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': actor, 'session_id': sid, 'role': 'authenticated', 'exp': expiry})}.${base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '')}';
  }

  Map<String, dynamic> get session => {
    'access_token': token(),
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': actor,
      'aud': 'authenticated',
      'role': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/rest/v1/company_members') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode([
              {'company_id': company, 'role': role},
            ]),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    expect(request.url.path, '/functions/v1/site-order-workflow');
    functions++;
    authorization =
        request.headers['Authorization'] ?? request.headers['authorization'];
    if (started?.isCompleted == false) started!.complete();
    await hold?.future;
    if (functionStatus != 200) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"result_unknown"}')),
        functionStatus,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    if (malformedSuccess)
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"result":{"status":"recipient_stored"}}')),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    return http.StreamedResponse(
      Stream.value(utf8.encode('%PDF-exact saved original')),
      200,
      headers: {'content-type': 'application/octet-stream'},
      request: request,
    );
  }
}

Future<(SupabaseClient, SiteOrderWorkflowRepository)> fixture(
  _Wire wire,
) async {
  final client = SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-public',
    httpClient: wire,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(jsonEncode(wire.session));
  await client.auth.recoverSession(jsonEncode(wire.session));
  return (client, SiteOrderWorkflowRepository(client));
}

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  test('restored pinned SDK session reads exact binary with captured token and manager membership', () async {
    final wire = _Wire(), f = await fixture(wire);
    addTearDown(f.$1.dispose);
    addTearDown(f.$2.dispose);
    final bytes = await f.$2.original(package, 'order');
    expect(ascii.decode(bytes), '%PDF-exact saved original');
    expect(wire.authorization, 'Bearer ${wire.token()}');
    expect(wire.functions, 1);
  });
  test('role change while binary is in flight retires scope and discards the late PDF', () async {
    final wire = _Wire()
      ..hold = Completer<void>()
      ..started = Completer<void>();
    final f = await fixture(wire);
    addTearDown(f.$1.dispose);
    addTearDown(f.$2.dispose);
    final pending = f.$2.original(package, 'order');
    final rejected = expectLater(pending, throwsStateError);
    await wire.started!.future;
    wire.role = 'worker';
    wire.hold!.complete();
    await rejected;
    expect(f.$2.invalidated, isTrue);
    expect(wire.functions, 1);
  });
  for (final status in [409, 500]) {
    test(
      'write status $status is UNKNOWN and the SDK request is never automatically retried',
      () async {
        final wire = _Wire()..functionStatus = status;
        final f = await fixture(wire);
        addTearDown(f.$1.dispose);
        addTearDown(f.$2.dispose);
        await expectLater(
          f.$2.resume(package),
          throwsA(isA<SiteOrderResultUnknown>()),
        );
        expect(wire.functions, 1);
      },
    );
  }
  test('a malformed success body cannot claim recipient storage', () async {
    final wire = _Wire()..malformedSuccess = true;
    final f = await fixture(wire);
    addTearDown(f.$1.dispose);
    addTearDown(f.$2.dispose);
    await expectLater(
      f.$2.resume(package),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(wire.functions, 1);
  });
}

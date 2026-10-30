import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:sk_works/features/sites/site_order_approval_journal.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const sid = '20000000-0000-0000-0000-000000000001';
const package = '30000000-0000-0000-0000-000000000001';

class _Wire extends http.BaseClient {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String role = 'manager';
  int functionStatus = 200;
  bool malformedSuccess = false;
  Map<String, dynamic>? functionJson;
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
    if (functionJson != null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(functionJson))),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    if (malformedSuccess) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"result":{"status":"recipient_stored"}}')),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('%PDF-exact saved original')),
      200,
      headers: {'content-type': 'application/octet-stream'},
      request: request,
    );
  }
}

class _FailingPreferences extends Fake implements SharedPreferences {
  _FailingPreferences(this.throwsOnWrite);
  final bool throwsOnWrite;
  @override
  Future<void> reload() async {}
  @override
  bool containsKey(String key) => false;
  @override
  String? getString(String key) => null;
  @override
  Future<bool> setString(String key, String value) async {
    if (throwsOnWrite) throw StateError('synthetic storage failure');
    return false;
  }
}

Future<(SupabaseClient, SiteOrderWorkflowRepository)> _fixture(
  _Wire wire, {
  SiteOrderApprovalJournal? approvalJournal,
}) async {
  final client = SupabaseClient(
    'https://synthetic.invalid',
    'synthetic-public',
    httpClient: wire,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.setInitialSession(jsonEncode(wire.session));
  await client.auth.recoverSession(jsonEncode(wire.session));
  return (
    client,
    SiteOrderWorkflowRepository(client, approvalJournal: approvalJournal),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('uncertain refusal survives reopen and fences approval until the exact barrier result', () async {
    final wire = _Wire()..functionStatus = 409;
    final f = await _fixture(wire);
    await expectLater(
      f.$2.refuse(package, package),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(wire.functions, 1);
    f.$2.dispose();
    final reopened = SiteOrderWorkflowRepository(f.$1);
    addTearDown(reopened.dispose);
    addTearDown(f.$1.dispose);
    expect(await reopened.hasPendingRefusal(package), isTrue);
    await expectLater(
      reopened.approve({
        'package_id': package,
        'preview_id': package,
        'body_hash': 'b' * 64,
        'own_seal': {'seal_hash': 'c' * 64},
      }, sid),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(wire.functions, 1);
    wire.functionStatus = 200;
    wire.functionJson = {
      'result': {
        'package_id': package,
        'request_id': package,
        'operation_state': 'cancelled',
      },
    };
    expect(await reopened.reconcileRefusal(package), 'cancelled');
    expect(await reopened.hasPendingRefusal(package), isFalse);
    expect(wire.functions, 2);
  });
  test(
    'corrupt refusal journal blocks any new refusal before network submission',
    () async {
      SharedPreferences.setMockInitialValues({
        'sko.site_order.refusal.v1.$actor.$company.$package':
            '{"request_id":"corrupt"}',
      });
      final wire = _Wire(), f = await _fixture(wire);
      addTearDown(f.$1.dispose);
      addTearDown(f.$2.dispose);
      await expectLater(f.$2.refuse(package, package), throwsStateError);
      expect(wire.functions, 0);
    },
  );
  for (final throwsOnWrite in [false, true]) {
    test(
      'approval sends no SDK HTTP request if durable storage fails ($throwsOnWrite)',
      () async {
        final wire = _Wire();
        final journal = SiteOrderApprovalJournal.withPreferences(
          () async => _FailingPreferences(throwsOnWrite),
        );
        final f = await _fixture(wire, approvalJournal: journal);
        addTearDown(f.$1.dispose);
        addTearDown(f.$2.dispose);
        await expectLater(
          f.$2.approve({
            'package_id': package,
            'preview_id': package,
            'body_hash': 'b' * 64,
            'own_seal': {'seal_hash': 'c' * 64},
          }, package),
          throwsStateError,
        );
        expect(wire.functions, 0);
      },
    );
  }
  test('unknown approval remains quarantined across repositories until exact server barrier resolves', () async {
    final wire = _Wire()..functionStatus = 409;
    final f = await _fixture(wire);
    final review = <String, dynamic>{
      'package_id': package,
      'preview_id': package,
      'body_hash': 'b' * 64,
      'own_seal': {'seal_hash': 'c' * 64},
    };
    await expectLater(
      f.$2.approve(review, package),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(wire.functions, 1);
    f.$2.dispose();
    final reopened = SiteOrderWorkflowRepository(f.$1);
    addTearDown(reopened.dispose);
    addTearDown(f.$1.dispose);
    expect(await reopened.hasPendingApproval(package), isTrue);
    await expectLater(
      reopened.approve(review, sid),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(wire.functions, 1);
    wire.functionStatus = 200;
    wire.functionJson = {
      'result': {
        'package_id': package,
        'preview_id': package,
        'request_id': sid,
        'operation_state': 'cancelled',
      },
    };
    await expectLater(
      reopened.reconcileApproval(package),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(await reopened.hasPendingApproval(package), isTrue);
    wire.functionJson = {
      'result': {
        'package_id': package,
        'preview_id': package,
        'request_id': package,
        'operation_state': 'cancelled',
      },
    };
    expect(await reopened.reconcileApproval(package), 'cancelled');
    expect(await reopened.hasPendingApproval(package), isFalse);
    expect(wire.functions, 3);
  });

  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  test('restored pinned SDK session reads exact binary with captured token and manager membership', () async {
    final wire = _Wire(), f = await _fixture(wire);
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
    final f = await _fixture(wire);
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
        final f = await _fixture(wire);
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
    final f = await _fixture(wire);
    addTearDown(f.$1.dispose);
    addTearDown(f.$2.dispose);
    await expectLater(
      f.$2.resume(package),
      throwsA(isA<SiteOrderResultUnknown>()),
    );
    expect(wire.functions, 1);
  });
}

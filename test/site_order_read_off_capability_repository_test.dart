import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _company = '10000000-0000-0000-0000-000000000002';
const _sid = '20000000-0000-0000-0000-000000000001';
const _package = '30000000-0000-0000-0000-000000000001';

// Actual SDK request/response unit fixture only, not GoTrue/RLS qualification.
class _Wire extends http.BaseClient {
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final capability = <String, dynamic>{
    'contract_version': 1,
    'workflow_contract_version': 1,
    'actor_id': _actor,
    'session_id': _sid,
    'company_id': _company,
    'role': 'manager',
    'master_enabled': false,
    'can_read': true,
    'can_create': true,
    'can_mutate': true,
  };
  int capabilityStatus = 200;
  int archiveRequests = 0;
  int mutationRequests = 0;
  String token() {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': _actor, 'session_id': _sid, 'role': 'authenticated', 'exp': expiry})}.${part('synthetic-signature')}';
  }

  Map<String, dynamic> get session => {
    'access_token': token(),
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': _actor,
      'aud': 'authenticated',
      'role': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
  http.StreamedResponse reply(
    http.BaseRequest r,
    Object value, {
    int status = 200,
  }) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(value))),
    status,
    headers: {'content-type': 'application/json'},
    request: r,
  );
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(
      request.headers['Authorization'] ?? request.headers['authorization'],
      'Bearer ${token()}',
    );
    switch (request.url.path) {
      case '/rest/v1/company_members':
        return reply(request, [
          {'company_id': _company, 'role': 'manager'},
        ]);
      case '/rest/v1/rpc/site_order_workflow_capabilities':
        return reply(
          request,
          capabilityStatus == 200 ? capability : {'code': 'PGRST202'},
          status: capabilityStatus,
        );
      case '/rest/v1/rpc/standalone_trade_document_access':
        return reply(request, {
          'contract_version': 1,
          'context_contract_version': 1,
          'actor_id': _actor,
          'session_id': _sid,
          'company_id': _company,
          'role': 'manager',
          'master_enabled': true,
          'can_generate': true,
        });
      case '/functions/v1/site-order-workflow':
        final body = jsonDecode((request as http.Request).body) as Map;
        expect(body['package_id'], _package);
        if (body['action'] == 'archive') {
          archiveRequests++;
          return http.StreamedResponse(
            Stream.value(utf8.encode('%PDF-synthetic saved original')),
            200,
            headers: {'content-type': 'application/octet-stream'},
            request: request,
          );
        }
        mutationRequests++;
        throw StateError('Unexpected mutation escaped capability guard');
      default:
        throw StateError('Unexpected fixture endpoint');
    }
  }
}

Future<(SupabaseClient, SiteOrderWorkflowRepository)> _fixture(
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
  final repository = SiteOrderWorkflowRepository(client);
  addTearDown(repository.dispose);
  addTearDown(client.dispose);
  return (client, repository);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'OFF reads saved original but cannot create or invoke a mutation',
    () async {
      final wire = _Wire();
      final f = await _fixture(wire);
      expect(await f.$2.canUseWorkflow(), isTrue);
      expect(
        utf8.decode(await f.$2.original(_package, 'order')),
        '%PDF-synthetic saved original',
      );
      expect(await f.$2.canCreateOutgoing(), isFalse);
      await expectLater(f.$2.resume(_package), throwsStateError);
      expect(wire.archiveRequests, 1);
      expect(wire.mutationRequests, 0);
    },
  );

  test(
    'read fails closed for malformed booleans and denied read receipt',
    () async {
      for (final change in <Map<String, dynamic>>[
        {'master_enabled': null},
        {'master_enabled': 'false'},
        {'master_enabled': 0},
        {'can_read': false},
        {'can_create': 'true'},
        {'can_mutate': 1},
      ]) {
        final wire = _Wire()..capability.addAll(change);
        final f = await _fixture(wire);
        expect(await f.$2.canUseWorkflow(), isFalse);
        await expectLater(f.$2.original(_package, 'order'), throwsStateError);
        expect(wire.archiveRequests, 0);
        expect(wire.mutationRequests, 0);
      }
    },
  );

  test(
    'OFF does not admit missing RPC unknown shape or stale scope receipt',
    () async {
      for (final change in <Map<String, dynamic>>[
        {'contract_version': 2},
        {'workflow_contract_version': 2},
        {'unexpected': true},
        {'actor_id': _company},
        {'session_id': _package},
        {'company_id': _actor},
        {'role': 'owner'},
      ]) {
        final wire = _Wire()..capability.addAll(change);
        final f = await _fixture(wire);
        expect(await f.$2.canUseWorkflow(), isFalse);
        await expectLater(
          f.$2.original(_package, 'acceptance'),
          throwsStateError,
        );
        expect(wire.archiveRequests, 0);
      }
      final wire = _Wire()..capabilityStatus = 404;
      final f = await _fixture(wire);
      expect(await f.$2.canUseWorkflow(), isFalse);
      expect(wire.archiveRequests, 0);
    },
  );

  test('ON still requires both explicit create and mutate grants', () async {
    final wire = _Wire()..capability['master_enabled'] = true;
    final f = await _fixture(wire);
    expect(await f.$2.canCreateOutgoing(), isTrue);
    wire.capability['can_mutate'] = false;
    expect(await f.$2.canUseWorkflow(), isTrue);
    expect(await f.$2.canCreateOutgoing(), isFalse);
    await expectLater(f.$2.resume(_package), throwsStateError);
    wire.capability['can_mutate'] = true;
    wire.capability['can_create'] = false;
    expect(await f.$2.canCreateOutgoing(), isFalse);
    expect(wire.mutationRequests, 0);
  });
}

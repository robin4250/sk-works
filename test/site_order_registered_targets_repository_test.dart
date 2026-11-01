import 'site_workflow_capability_fixture.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sk_works/features/sites/site_order_outgoing_entries.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _id(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> _synthetic() {
  Map<String, dynamic> page(int start, int count, bool more) => {
    'contract_version': 1,
    'actor_id': _id(1),
    'company_id': _id(2),
    'session_id': _id(4),
    'site_id': _id(3),
    'entries': [
      for (var n = start; n < start + count; n++)
        {'id': _id(100 + n), 'name': '合成登録会社'},
    ],
    'has_more': more,
    'next_cursor': more ? _id(100 + start + count - 1) : null,
    'read_only': true,
    'can_send': false,
  };
  return {
    'actor': _id(1),
    'company': _id(2),
    'session': _id(4),
    'site': _id(3),
    'pages': [page(0, 50, true), page(50, 3, false)],
  };
}

class _Wire extends http.BaseClient {
  _Wire(Map<String, dynamic> data)
    : data = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
  final Map<String, dynamic> data;
  String mode = 'valid';
  int calls = 0;
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String token() {
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': data['actor'], 'session_id': data['session'], 'role': 'authenticated', 'exp': expiry})}.${part('synthetic-signature')}';
  }

  Map<String, dynamic> get session => {
    'access_token': token(),
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'expires_at': expiry,
    'token_type': 'bearer',
    'user': {
      'id': data['actor'],
      'aud': 'authenticated',
      'role': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/rest/v1/rpc/site_order_workflow_capabilities') {
      return supportedSiteWorkflowCapability(request, actor: data['actor'], company: data['company'], session: data['session']);
    }
    Object body;
    int status = 200;
    if (request.url.path == '/rest/v1/company_members') {
      body = [
        {'company_id': data['company'], 'role': 'manager'},
      ];
    } else {
      expect(request.url.path, '/functions/v1/site-order-workflow/outgoing');
      expect(
        request.headers['Authorization'] ?? request.headers['authorization'],
        'Bearer ${token()}',
      );
      final command = jsonDecode((request as http.Request).body) as Map;
      expect(command.keys.toSet(), {'action', 'site_id', 'before', 'limit'});
      expect(command['action'], 'targets');
      expect(command['site_id'], data['site']);
      expect(command['limit'], 50);
      final pages = data['pages'] as List, index = calls++;
      expect(
        command['before'],
        index == 0 ? null : (pages[index - 1] as Map)['next_cursor'],
      );
      if (mode == 'unknown-after-first' && index > 0) {
        status = 409;
        body = {'error': 'result_unknown'};
      } else {
        final page = Map<String, dynamic>.from(
          pages[mode == 'repeat-first' ? 0 : index] as Map,
        );
        if (mode == 'foreign-company') page['company_id'] = _id(999);
        if (mode == 'foreign-session') page['session_id'] = _id(998);
        if (mode == 'non-list') page['entries'] = 'unknown';
        if (mode == 'extra-data') {
          final rows = page['entries'] as List;
          rows[0] = {...rows[0] as Map, 'phone': 'must-not-expose'};
        }
        if (mode == 'wrong-cursor') page['next_cursor'] = _id(997);
        body = {'result': page};
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Future<(SupabaseClient, SiteOrderWorkflowRepository)> _repository(
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
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> accept(Map<String, dynamic> data) async {
    final wire = _Wire(data);
    final (client, repository) = await _repository(wire);
    try {
      final rows = await repository.registeredOutgoingTargets(
        data['site'] as String,
      );
      final expected = [
        for (final page in data['pages'] as List) ...(page['entries'] as List),
      ];
      expect(rows.map((r) => {'id': r.id, 'name': r.name}).toList(), expected);
      expect(wire.calls, (data['pages'] as List).length);
      expect(
        () => rows.add(
          const SiteOrderRegisteredTarget(id: 'never', name: 'never'),
        ),
        throwsUnsupportedError,
      );
    } finally {
      repository.dispose();
      await client.dispose();
    }
  }

  test(
    'actual SDK traverses strict identity-only pages without directory synchronization',
    () => accept(_synthetic()),
  );
  for (final mode in [
    'foreign-company',
    'foreign-session',
    'non-list',
    'extra-data',
    'wrong-cursor',
    'repeat-first',
    'unknown-after-first',
  ]) {
    test('SDK $mode returns no misleading partial target list', () async {
      final data = _synthetic(), wire = _Wire(data)..mode = mode;
      final (client, repository) = await _repository(wire);
      try {
        await expectLater(
          repository.registeredOutgoingTargets(data['site'] as String),
          throwsA(anything),
        );
        expect(wire.calls, lessThanOrEqualTo(2));
      } finally {
        repository.dispose();
        await client.dispose();
      }
    });
  }
  final nativePath = Platform.environment['SKO_TARGET_FIXTURE_RECEIPT_PATH'];
  test(
    'Native-generated target receipts cross actual SDK repository decoding',
    () async {
      final raw = jsonDecode(await File(nativePath!).readAsString());
      await accept(Map<String, dynamic>.from(raw as Map));
    },
    skip: nativePath == null
        ? 'dedicated workflow supplies Native PostgreSQL receipt artifact'
        : false,
  );
}

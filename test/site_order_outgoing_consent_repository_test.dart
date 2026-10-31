import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_workflow_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _id(int n) => '92000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> _synthetic() {
  final evidence = jsonDecode(
    File('tool/canonical_renderer/synthetic-evidence.json').readAsStringSync(),
  ) as Map;
  final company = (evidence['body'] as Map)['issuer_company_id'];
  final identity = {
    'site_id': _id(10),
    'document_id': _id(11),
    'local_id': _id(12),
    'trade_id': _id(13),
    'request_id': _id(14),
  };
  final preview = {
    'purpose': 'unsigned_review',
    'preview_only': true,
    'can_register': false,
    'can_send': false,
    'preview_id': _id(15),
    'operation_id': _id(16),
    'document_id': identity['document_id'],
    'revision': 1,
    'body_hash': 'a' * 64,
    'source_hash': 'b' * 64,
    'seal_hash': (evidence['seals'] as List).single['seal_hash'],
    'renderer_contract': 'sko-original-form-20261029-v1',
    'body': evidence['body'],
    'own_seal': (evidence['seals'] as List).single,
  };
  final result = {
    'contract_version': 1,
    'operation_state': 'decision_job_prepared',
    'decision_request_id': _id(17),
    'preview_id': _id(15),
    'operation_id': _id(16),
    'job_id': _id(18),
    'company_id': company,
    'site_id': identity['site_id'],
    'document_id': identity['document_id'],
    'local_document_id': identity['local_id'],
    'trade_company_id': identity['trade_id'],
    'request_id': identity['request_id'],
    'body_hash': 'a' * 64,
    'render_hash': 'c' * 64,
    'original_registered': false,
    'sent': false,
    'can_send': false,
    'journal_clearable': false,
    'retry_automatically': false,
    'read_only': true,
    'same_session': true,
  };
  return {
    'actor': _id(1),
    'company': company,
    'session': _id(2),
    'identity': identity,
    'decision_id': _id(17),
    'preview': preview,
    'result': result,
  };
}

class _Wire extends http.BaseClient {
  _Wire(Map<String, dynamic> input)
    : data = Map<String, dynamic>.from(jsonDecode(jsonEncode(input)) as Map);
  final Map<String, dynamic> data;
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String mode = 'valid';
  int mutations = 0;
  int statuses = 0, prepareMutations = 0, prepareStatuses = 0;
  Map<String, dynamic> preparedReceipt({required bool observation}) {
    final identity = data['identity'] as Map;
    final preview = data['preview'] as Map;
    final result = data['prepared'] is Map
        ? Map<String, dynamic>.from(data['prepared'] as Map)
        : <String, dynamic>{
            'contract_version': 1,
            'operation_state': 'prepared_review_required',
            'operation_id': preview['operation_id'],
            'company_id': data['company'],
            'request_id': identity['request_id'],
            'site_id': identity['site_id'],
            'document_id': identity['document_id'],
            'local_document_id': identity['local_id'],
            'trade_company_id': identity['trade_id'],
            'body_hash': preview['body_hash'],
            'source_hash': preview['source_hash'],
            'seal_hash': preview['seal_hash'],
            'prepared_at': '2026-10-31T00:00:00Z',
            'retired': false,
            'journal_clearable': false,
            'retry_automatically': false,
            'may_prepare_again': false,
            'can_send': false,
          };
    result.remove('same_session');
    result.remove('requires_fresh_review');
    if (observation) {
      result['same_session'] = mode != 'different-prepare-session';
      result['requires_fresh_review'] = true;
    }
    if (mode == 'advanced-prepare') result['operation_state'] = 'advanced';
    return result;
  }

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
    Object body;
    int status = 200;
    if (request.url.path == '/rest/v1/company_members') {
      body = [
        {'company_id': data['company'], 'role': 'manager'},
      ];
    } else if (request.url.path ==
        '/rest/v1/rpc/standalone_trade_document_access') {
      expect(
        request.headers['Authorization'] ?? request.headers['authorization'],
        'Bearer ${token()}',
      );
      final receipt = {
        'contract_version': 1,
        'context_contract_version': 1,
        'actor_id': data['actor'],
        'company_id': data['company'],
        'session_id': data['session'],
        'role': 'manager',
        'master_enabled': true,
        'can_generate': true,
      };
      if (mode == 'gate-off') {
        status = 403;
        body = {'message': 'master_feature_disabled'};
      } else {
        if (mode == 'gate-forged-company') receipt['company_id'] = _id(900);
        if (mode == 'gate-forged-session') receipt['session_id'] = _id(901);
        if (mode == 'gate-extra') receipt['untrusted'] = true;
        body = receipt;
      }
    } else {
      expect(request.url.path, '/functions/v1/site-order-workflow/outgoing');
      final command = jsonDecode((request as http.Request).body) as Map;
      final identity = data['identity'] as Map;
      for (final entry in identity.entries) {
        expect(command[entry.key], entry.value);
      }
      if (command['action'] == 'prepare') {
        prepareMutations++;
        expect(command.length, 8);
        expect(
          command['body'],
          data['input_body'] ?? (data['preview'] as Map)['body'],
        );
        final p = await SharedPreferences.getInstance();
        expect(
          p
              .getKeys()
              .where((k) => k.startsWith('sko.site_order.outgoing.v1.'))
              .length,
          1,
        );
        if (mode == 'prepare-unknown') {
          status = 409;
          body = {'error': 'result_unknown'};
        } else {
          body = {'result': preparedReceipt(observation: false)};
        }
      } else if (command['action'] == 'status') {
        prepareStatuses++;
        expect(command.length, 6);
        body = {'result': preparedReceipt(observation: true)};
      } else if (command['action'] == 'preview_unsigned') {
        expect(command.length, 6);
        body = {'result': data['preview']};
      } else {
        expect(command['preview_id'], (data['preview'] as Map)['preview_id']);
        expect(command['decision_id'], data['decision_id']);
        final result = Map<String, dynamic>.from(data['result'] as Map);
        if (command['action'] == 'confirm_unsigned') {
          mutations++;
          expect(command.length, 9);
          expect(command['confirmed'], true);
          final p = await SharedPreferences.getInstance();
          expect(
            p
                .getKeys()
                .where((k) => k.startsWith('sko.site_order.consent.v1.'))
                .length,
            1,
          );
          result.remove('read_only');
          result.remove('same_session');
          if (mode == 'unknown') {
            status = 409;
          }
        } else {
          expect(command['action'], 'decision_status');
          expect(command.length, 8);
          statuses++;
          if (mode == 'not-observed') {
            result
              ..clear()
              ..addAll({
                'contract_version': 1,
                'operation_state': 'decision_not_observed',
                'can_send': false,
                'retry_automatically': false,
                'journal_clearable': false,
                'read_only': true,
                'same_session': false,
              });
          }
        }
        if (mode == 'wrong-job-binding') {
          result['document_id'] = _id(999);
        }
        if (mode == 'fresh-session') {
          result['same_session'] = false;
        }
        if (mode == 'clearable') {
          result['journal_clearable'] = true;
        }
        body = status == 409 ? {'error': 'result_unknown'} : {'result': result};
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

SiteOrderPendingPrepare _prepare(Map<String, dynamic> data) =>
    SiteOrderPendingPrepare.fromJson({
      ...data['identity'] as Map,
      'session_id': data['session'],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> accept(Map<String, dynamic> data) async {
    final wire = _Wire(data);
    final (client, repository) = await _repository(wire);
    try {
      final preview = await repository.previewUnsignedOutgoing(_prepare(data));
      final reference = SiteOrderConsentReference.fromPreview(
        _prepare(data),
        preview,
        data['decision_id'] as String,
      );
      await expectLater(
        repository.confirmUnsignedOutgoing(reference, confirmed: false),
        throwsStateError,
      );
      expect(wire.mutations, 0);
      wire.mode = 'unknown';
      await expectLater(
        repository.confirmUnsignedOutgoing(reference, confirmed: true),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      expect(wire.mutations, 1);
      await expectLater(
        repository.confirmUnsignedOutgoing(reference, confirmed: true),
        throwsStateError,
      );
      expect(wire.mutations, 1);
      final pending = await repository.pendingOutgoingConsents(
        reference.prepare.siteId,
      );
      expect(pending.single.toJson(), reference.toJson());
      final restored = SiteOrderWorkflowRepository(client);
      try {
        final recovered = await restored.pendingOutgoingConsents(
          reference.prepare.siteId,
        );
        expect(recovered.single.toJson(), reference.toJson());
        final preferences = await SharedPreferences.getInstance();
        final stored = preferences.getString(preferences.getKeys().single)!;
        expect(jsonDecode(stored), reference.toJson());
        expect(stored.contains('seal_snapshot'), false);
        expect(stored.contains('issuer'), false);
      } finally {
        restored.dispose();
      }
      wire.mode = 'valid';
      final observed = await repository.inspectOutgoingConsent(pending.single);
      expect(observed.jobId, (data['result'] as Map)['job_id']);
      expect(observed.canSend, false);
      expect(observed.journalClearable, false);
      expect(wire.mutations, 1);
      expect(wire.statuses, 1);
      wire.mode = 'not-observed';
      final unknown = await repository.inspectOutgoingConsent(reference);
      expect(unknown.observed, false);
      expect(unknown.retryAutomatically, false);
      expect(
        (await repository.pendingOutgoingConsents(reference.prepare.siteId))
            .length,
        1,
      );
      for (final mode in ['wrong-job-binding', 'clearable']) {
        wire.mode = mode;
        await expectLater(
          repository.inspectOutgoingConsent(reference),
          throwsStateError,
        );
      }
      expect(wire.mutations, 1);
    } finally {
      repository.dispose();
      await client.dispose();
    }
  }

  test(
    'actual SDK keeps unknown decision IDs and only reads status after ACK loss',
    () => accept(_synthetic()),
  );
  test('new live SDK session can only inspect old decision identity', () async {
    final original = _synthetic();
    final rawPreview = original['preview'] as Map;
    final reference = SiteOrderConsentReference(
      prepare: _prepare(original),
      previewId: rawPreview['preview_id'],
      operationId: rawPreview['operation_id'],
      decisionId: original['decision_id'] as String,
      bodyHash: rawPreview['body_hash'],
    );
    final wire = _Wire({...original, 'session': _id(80)})
      ..mode = 'fresh-session';
    final (client, repository) = await _repository(wire);
    try {
      await expectLater(
        repository.confirmUnsignedOutgoing(reference, confirmed: true),
        throwsStateError,
      );
      expect(wire.mutations, 0);
      final observed = await repository.inspectOutgoingConsent(reference);
      expect(observed.observed, true);
      expect(observed.canSend, false);
      expect(wire.mutations, 0);
    } finally {
      repository.dispose();
      await client.dispose();
    }
  });
  Future<void> prepareAccept(Map<String, dynamic> data) async {
    final wire = _Wire(data)..mode = 'prepare-unknown';
    final (client, repository) = await _repository(wire);
    final entry = _prepare(data);
    try {
      expect(await repository.canCreateOutgoing(), true);
      final input = Map<String, dynamic>.from(
        (data['input_body'] ?? (data['preview'] as Map)['body']) as Map,
      );
      // Synthetic case uses the same identity relationship as the real Native artifact.
      input['transaction_id'] = entry.documentId;
      wire.data['input_body'] = input;
      await expectLater(
        repository.prepareUnsignedOutgoing(
          entry,
          input,
          data['connection_fingerprint'] as String? ?? 'a' * 64,
        ),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      expect(wire.prepareMutations, 1);
      await expectLater(
        repository.prepareUnsignedOutgoing(entry, input, 'a' * 64),
        throwsStateError,
      );
      expect(wire.prepareMutations, 1);
      expect(
        (await repository.pendingOutgoing(entry.siteId)).single.toJson(),
        entry.toJson(),
      );
      wire.mode = 'valid';
      expect(
        await repository.inspectUnsignedForReview(entry),
        'prepared_review_required',
      );
      expect(wire.prepareMutations, 1);
      expect(wire.prepareStatuses, 1);
      wire.mode = 'different-prepare-session';
      await expectLater(
        repository.inspectUnsignedForReview(entry),
        throwsA(isA<SiteOrderResultUnknown>()),
      );
      expect(wire.prepareMutations, 1);
    } finally {
      repository.dispose();
      await client.dispose();
    }
  }

  test(
    'actual SDK journals prepare before uncertain write and resolves only same-SID status',
    () => prepareAccept(_synthetic()),
  );
  for (final mode in [
    'gate-off',
    'gate-forged-company',
    'gate-forged-session',
    'gate-extra',
  ]) {
    test('creation gate $mode fails closed without a write', () async {
      final wire = _Wire(_synthetic())..mode = mode;
      final (client, repository) = await _repository(wire);
      try {
        expect(await repository.canCreateOutgoing(), false);
        expect(wire.prepareMutations, 0);
      } finally {
        repository.dispose();
        await client.dispose();
      }
    });
  }
  final native = Platform.environment['SKO_CONSENT_RECEIPT_PATH'];
  test(
    'Native prepared status crosses actual SDK prepare quarantine and review gate',
    () async {
      await prepareAccept(
        Map<String, dynamic>.from(
          jsonDecode(await File(native!).readAsString()) as Map,
        ),
      );
    },
    skip: native == null
        ? 'dedicated CI supplies Native receipt artifact'
        : false,
  );
  test(
    'Native ES256 SQL receipt crosses actual SDK and journal decoding',
    () async {
      await accept(
        Map<String, dynamic>.from(
          jsonDecode(await File(native!).readAsString()) as Map,
        ),
      );
    },
    skip: native == null
        ? 'dedicated CI supplies Native receipt artifact'
        : false,
  );
}

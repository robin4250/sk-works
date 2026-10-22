import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/company_common_allowance_repository.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_command.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_controller.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_pending_store.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_repository.dart';
import 'package:sk_works/features/payroll/company_common_payroll_publication_repository.dart';
import 'support/common_canonical_client_fixture.dart';

void main() {
  Map<String, dynamic> actualSql() => Map<String, dynamic>.from(jsonDecode(
    File('test/fixtures/company_common_canonical_publication_contract3.json').readAsStringSync()) as Map);
  test('actual synthetic SQL export matches company state, approved command, preview and receipt parsers', () {
    final sql = actualSql();
    final command = CommonPayrollCanonicalPublicationCommand.fromParams(sql['command']);
    final settings = CompanyCommonAllowanceState.parse(sql['company_state'], command.companyId);
    final timeline = CommonPayrollPublicationState.parse((sql['preview'] as Map)['timeline'], command.companyId);
    final generated = canonicalCommonPayrollPreviewParams(settings, timeline, command.payrollType, command.startsOn);
    expect(generated, (sql['preview'] as Map)['command_base']);
    final preview = CommonPayrollCanonicalPublicationPreview.parse(sql['preview'], generated);
    final approval = preview.approve(activation: true, selectedDays: true);
    final samePayload = Map<String, dynamic>.from(approval.params)..['p_request_id'] = command.requestId;
    expect(samePayload, command.params);
    expect(CommonPayrollCanonicalPublicationResult.parse(sql['publish_result'], command).targetCount, preview.targetCount);
    expect(CommonPayrollCanonicalPublicationResult.parse((sql['receipt_found'] as Map)['result'], command).excludedCount, preview.excludedCount);
    expect((sql['receipt_missing'] as Map)['found'], false);
  });
  test('real SDK consumes actual synthetic SQL preview, publish and read-only receipt responses', () async {
    final sql = actualSql();
    final command = CommonPayrollCanonicalPublicationCommand.fromParams(sql['command']);
    final user = {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
      'email': 'fixture@example.invalid', 'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}};
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token = '${part({'alg': 'HS256'})}.${part({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
    final endpoints = <String>[];
    final client = SupabaseClient('https://fixture.invalid', 'fixture-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
        Object? value;
        if (request.url.path == '/auth/v1/token') {
          value = {'access_token': token, 'refresh_token': 'fixture', 'token_type': 'bearer', 'expires_in': 3600, 'user': user};
        } else {
          final name = request.url.path.split('/').last;
          endpoints.add(name);
          expect(request.headers['Authorization'], 'Bearer $token');
          if (name == 'company_common_payroll_publication_v2_contract_version') {
            value = 3;
          } else if (name == 'preview_company_common_payroll_v2') {
            expect(jsonDecode(request.body), (sql['preview'] as Map)['command_base']); value = sql['preview'];
          } else if (name == 'publish_company_common_payroll_v2') {
            expect(jsonDecode(request.body), command.params); value = sql['publish_result'];
          } else if (name == 'read_company_common_payroll_publish_receipt_v2') {
            expect(jsonDecode(request.body), command.receiptParams); value = sql['receipt_found'];
          } else { throw StateError('unexpected fixture endpoint'); }
        }
        return http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
    final repository = SupabaseCommonPayrollCanonicalPublicationRepository(client);
    expect(await repository.available(), true);
    final parsed = await repository.preview(Map<String, dynamic>.from((sql['preview'] as Map)['command_base'] as Map));
    expect((await repository.publish(command)).targetCount, parsed.targetCount);
    expect((await repository.receipt(command))!.excludedCount, parsed.excludedCount);
    expect(endpoints.where((e) => e == 'publish_company_common_payroll_v2').length, 1);
  });
  test('preview and result reject different scope, counts or receipt timeline', () {
    final wrong = previewJson()..['target_count'] = 0;
    expect(() => CommonPayrollCanonicalPublicationPreview.parse(wrong, base()), throwsFormatException);
    final changed = previewJson()..['command_base'] = {...base(), 'p_company_id': actor};
    expect(() => CommonPayrollCanonicalPublicationPreview.parse(changed, base()), throwsFormatException);
    final incomplete = resultJson()..['timeline'] = timeline();
    expect(() => CommonPayrollCanonicalPublicationResult.parse(incomplete, command()), throwsFormatException);
    final valid = CommonPayrollCanonicalPublicationPreview.parse(previewJson(), base());
    expect(() => valid.approve(activation: false, selectedDays: true), throwsStateError);
    expect(valid.approve(activation: true, selectedDays: true).companyId, company);
  });
  test('old company-wide activation contract is rejected; existing legacy boundary remains explicit', () {
    final old = previewJson()..['contract_version'] = 2;
    expect(() => CommonPayrollCanonicalPublicationPreview.parse(old, base()), throwsFormatException);
    final globalStart = previewJson()
      ..['activation_scope'] = 'legacy_company'
      ..['activation_mode'] = 'legacy_global';
    expect(() => CommonPayrollCanonicalPublicationPreview.parse(globalStart, base()), throwsFormatException);
    final blocked = {...globalStart, 'ready': false,
      'activation_blockers': ['legacy_global_boundary_advance_requires_review']};
    expect(CommonPayrollCanonicalPublicationPreview.parse(blocked, base()).ready, false);
    final existing = {...globalStart, 'activation_required': false};
    final preview = CommonPayrollCanonicalPublicationPreview.parse(existing, base());
    expect(preview.approve(activation: false, selectedDays: true).activationScope, 'legacy_company');
    expect(() => preview.approve(activation: true, selectedDays: true), throwsFormatException);
  });
  test('unknown commit survives recreation and lookup never issues another publish', () async {
    final root = await Directory.systemTemp.createTemp('canonical-controller-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FakeCanonicalRepository()..publishError = StateError('fixture transport unknown');
    FileCommonPayrollCanonicalPublicationPendingStore store() =>
      FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => repository.actorId, directory: () async => root);
    final first = CommonPayrollCanonicalPublicationController(companyId: company, repository: repository, store: store());
    await first.load();
    repository.beforePublish = () async => expect((await store().read(actor, company))!.command.params, command().params);
    await expectLater(first.publish(command()), throwsStateError);
    expect(repository.publishes, 1);
    final restored = CommonPayrollCanonicalPublicationController(companyId: company, repository: repository, store: store());
    await restored.load();
    expect(await restored.lookup(), isNull);
    expect(restored.pending, isNotNull);
    await expectLater(restored.publish(command()), throwsStateError);
    repository.receiptError = const PostgrestException(message: 'fixture permission denial', code: '42501');
    await expectLater(restored.lookup(), throwsA(isA<PostgrestException>()));
    expect(await store().read(actor, company), isNotNull);
    repository..receiptError = null..found = true;
    expect((await restored.lookup())!.targetCount, 1);
    expect(repository.publishes, 1);
    expect(repository.receiptCommands.every((p) => canonicalPublicationJson(p) == canonicalPublicationJson(command().receiptParams)), true);
    expect(await store().read(actor, company), isNull);
  });
  test('explicit first-attempt PostgreSQL rollback clears only that pending command', () async {
    final root = await Directory.systemTemp.createTemp('canonical-controller-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FakeCanonicalRepository()..publishError = const PostgrestException(message: 'fixture stale preview', code: '40001');
    final store = FileCommonPayrollCanonicalPublicationPendingStore(currentActor: () => actor, directory: () async => root);
    final controller = CommonPayrollCanonicalPublicationController(companyId: company, repository: repository, store: store);
    await controller.load();
    await expectLater(controller.publish(command()), throwsA(isA<PostgrestException>()));
    expect(controller.pending, isNull);
    expect(await store.read(actor, company), isNull);
  });
  for (final capability in <Object>[2, '3', 3.0, 3]) {
    test('real SDK probes capability before versioned requests: $capability (${capability.runtimeType})', () async {
      final user = {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
        'email': 'fixture@example.invalid', 'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': {}, 'user_metadata': {}};
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      final calls = <String>[];
      final client = SupabaseClient('https://fixture.invalid', 'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          Object? value;
          if (request.url.path == '/auth/v1/token') {
            value = {'access_token': token, 'refresh_token': 'fixture', 'token_type': 'bearer', 'expires_in': 3600, 'user': user};
          } else {
            calls.add(request.url.path);
            expect(request.headers['Authorization'], 'Bearer $token');
            if (request.url.path.endsWith('/company_common_payroll_publication_v2_contract_version')) {
              value = capability;
            } else if (request.url.path.endsWith('/preview_company_common_payroll_v2')) {
              value = previewJson();
            } else if (request.url.path.endsWith('/read_company_common_payroll_publish_receipt_v2')) {
              expect(jsonDecode(request.body), command().receiptParams);
              value = {'contract_version': 3, 'found': false};
            } else { throw StateError('unexpected fixture endpoint'); }
          }
          return http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'}, request: request);
        }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
      final repository = SupabaseCommonPayrollCanonicalPublicationRepository(client);
      await expectLater(repository.preview(base()), throwsStateError);
      final available = await repository.available();
      expect(available, capability is int && capability == 3);
      if (available) {
        expect((await repository.preview(base())).targetCount, 1);
        expect(await repository.receipt(command()), isNull);
      } else {
        await expectLater(repository.preview(base()), throwsStateError);
        expect(calls.length, 1);
      }
    });
  }
}

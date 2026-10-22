import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_command.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_controller.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_pending_store.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_repository.dart';
import 'package:sk_works/features/payroll/company_common_payroll_publication_repository.dart';

const actor = '00000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000001';
const requestId = '80000000-0000-0000-0000-000000000001';
Map<String, dynamic> base() => {
  'p_company_id': company, 'p_payroll_type': 'monthly', 'p_starts_on': '2026-10-01',
  'p_common_version': 3, 'p_common_source': {'fixture_source': 'original'},
  'p_timeline_version': 0, 'p_legacy_quantities': [],
  'p_individual_reconciliation': CommonPayrollCanonicalPublicationCommand.reconciliation,
};
Map<String, dynamic> timeline({int version = 0}) => {
  'contract_version': 1, 'company_id': company, 'can_edit': true,
  'timeline_version': version, 'common_version': 3, 'common_source': {'fixture_source': 'original'},
  'entries': [if (version == 1) {'version': 1, 'payroll_type': 'monthly',
    'starts_on': '2026-10-01', 'request_id': requestId}],
};
Map<String, dynamic> scope({String status = 'target_draft'}) => {
  'worker_id': '40000000-0000-0000-0000-000000000001',
  'month': '2026-10-01', 'status': status, 'reasons': [], 'selection_classification': [],
};
Map<String, dynamic> previewJson() => {
  'contract_version': 3, 'ready': true, 'preview_token': List.filled(64, 'a').join(),
  'command_base': base(), 'activation_required': true, 'target_count': 1,
  'activation_scope': 'payroll_type', 'activation_mode': 'per_type',
  'excluded_count': 0, 'unresolved_count': 0, 'scopes': [scope()], 'items': [],
  'next_effective_boundary': null, 'timeline': timeline(),
};
CommonPayrollCanonicalPublicationCommand command() =>
    CommonPayrollCanonicalPublicationCommand.fromParams({...base(), 'p_request_id': requestId,
      'p_preview_token': List.filled(64, 'a').join(), 'p_approve_activation': true,
      'p_activation_scope': 'payroll_type'});
Map<String, dynamic> resultJson() => {
  'contract_version': 3, 'company_id': company, 'request_id': requestId,
  'publication_version': 1, 'starts_on': '2026-10-01', 'payroll_type': 'monthly',
  'recalculated_scopes': 1, 'excluded_scopes': 0, 'unresolved_scopes': 0,
  'activation_changed': true, 'scopes': [{...scope(), 'readback_status': 'verified',
    'statement_md5_after': List.filled(32, 'b').join()}], 'timeline': timeline(version: 1),
};

class FakeCanonicalRepository implements CommonPayrollCanonicalPublicationRepository {
  String? key = 'fixture-session';
  int publishes = 0;
  Object? publishError, receiptError;
  bool found = false;
  Future<void> Function()? beforePublish;
  final receiptCommands = <Map<String, dynamic>>[];
  @override String? get actorId => actor;
  @override String? get sessionKey => key;
  @override Stream<String?> get sessionChanges => const Stream.empty();
  @override Future<bool> available() async => true;
  @override Future<CommonPayrollPublicationState> read(String companyId) async =>
    CommonPayrollPublicationState.parse(timeline(), companyId);
  @override Future<CommonPayrollCanonicalPublicationPreview> preview(Map<String, dynamic> params) async =>
    CommonPayrollCanonicalPublicationPreview.parse(previewJson(), params);
  @override Future<CommonPayrollCanonicalPublicationResult> publish(CommonPayrollCanonicalPublicationCommand value) async {
    publishes++;
    await beforePublish?.call();
    if (publishError != null) throw publishError!;
    return CommonPayrollCanonicalPublicationResult.parse(resultJson(), value);
  }
  @override Future<CommonPayrollCanonicalPublicationResult?> receipt(CommonPayrollCanonicalPublicationCommand value) async {
    receiptCommands.add(value.receiptParams);
    if (receiptError != null) throw receiptError!;
    return found ? CommonPayrollCanonicalPublicationResult.parse(resultJson(), value) : null;
  }
}

void main() {
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
    await expectLater(restored.lookup(), isA<PostgrestException>());
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
    await expectLater(controller.publish(command()), isA<PostgrestException>());
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
            if (request.url.path.endsWith('/company_common_payroll_publication_v2_contract_version')) value = capability;
            else if (request.url.path.endsWith('/preview_company_common_payroll_v2')) value = previewJson();
            else if (request.url.path.endsWith('/read_company_common_payroll_publish_receipt_v2')) {
              expect(jsonDecode(request.body), command().receiptParams);
              value = {'contract_version': 3, 'found': false};
            } else { throw StateError('unexpected fixture endpoint'); }
          }
          return http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'});
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

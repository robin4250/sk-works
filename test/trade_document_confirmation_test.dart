import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_controller.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_model.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_pending_store.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_repository.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_approved_pdf.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_dialog.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '20000000-0000-0000-0000-000000000001';
const parent = '30000000-0000-0000-0000-000000000001';
const local = '40000000-0000-0000-0000-000000000001';
const document = '50000000-0000-0000-0000-000000000001';
Map<String, dynamic> descriptor({String kind = 'invoice'}) => {
  'contract_version': 1, 'kind': kind, 'company_id': company, 'actor_id': actor,
  'parent_id': parent, 'source_revision': '2026-10-22T00:00:00Z', 'attachment_version': 2,
  'local_document_id': local, 'document_id': document, 'document_revision': 1,
  'body_hash': List.filled(64, 'a').join(), 'preview_hash': List.filled(64, 'b').join(),
};
Map<String, dynamic> result(TradeConfirmationCommand command) => {
  'contract_version': 1, 'kind': command.expected.kind, 'company_id': company, 'actor_id': actor,
  'local_document_id': local, 'document_id': document, 'document_revision': 1,
  'request_id': command.requestId, 'seal_consent_recorded': true,
  'operation': command.expected.kind == 'invoice' ? 'invoice_final_approval_with_seal' : 'monthly_content_review_with_seal',
  'result': {'document_id': document, 'revision': 1, 'request_id': command.requestId,
    'seal_consent_recorded': true, if (command.expected.kind == 'invoice') 'financial_approved': true
    else ...{'monthly_review_recorded': true, 'financial_finalized': false, 'financial_parent_unchanged': true}},
};

class FakeRepository implements TradeConfirmationRepository {
  String? actor = actorIdValue, token = 'fixture-session';
  static const actorIdValue = '10000000-0000-0000-0000-000000000001';
  final changes = StreamController<String?>.broadcast();
  int confirms = 0, lookups = 0;
  Object? error, receiptError;
  Object? capabilityError;
  bool capability = true;
  bool found = false;
  Future<void> Function(TradeConfirmationCommand)? beforeConfirm;
  @override String? get actorId => actor;
  @override String? get sessionKey => token;
  @override Stream<String?> get sessionChanges => changes.stream;
  @override Future<bool> available() async {
    if (capabilityError != null) throw capabilityError!;
    return capability;
  }
  @override Future<TradeConfirmationResult> confirm(TradeConfirmationCommand command) async {
    confirms++; await beforeConfirm?.call(command);
    if (error != null) throw error!;
    return TradeConfirmationResult.parse(result(command), command);
  }
  @override Future<TradeConfirmationResult?> receipt(TradeConfirmationCommand command) async {
    lookups++;
    if (receiptError != null) throw receiptError!;
    return found ? TradeConfirmationResult.parse(result(command), command) : null;
  }
  @override Future<TradeConfirmationWorkspace> workspace(String kind, String parentId, String revision) async =>
    TradeConfirmationWorkspace.parse({'contract_version': 1, 'kind': kind, 'company_id': company,
      'actor_id': actorId, 'parent_id': parentId, 'source_revision': revision, 'side': 'issued',
      'integration_required': false, 'can_integrated_confirm': false, 'can_render': false, 'unavailable_reason': null},
      kind: kind, parentId: parentId, sourceRevision: revision, actorId: actorId!);
  @override Future<Map<String, dynamic>> resolve(String kind, String parentId) => throw UnimplementedError();
  @override Future<TradeConfirmationPreview> preview(TradeConfirmationWorkspace workspace) => throw UnimplementedError();
  @override Future<Map<String, dynamic>> render(Map<String, dynamic> scope, {bool archive = false}) => throw UnimplementedError();
  @override Future<Map<String, dynamic>> received(String tradeCompanyId) => throw UnimplementedError();
  @override Future<Map<String, dynamic>> receive(String tradeCompanyId, String documentId, int revision) => throw UnimplementedError();
}

class MemoryStore implements TradeConfirmationPendingStore {
  TradeConfirmationPending? value;
  @override Future<TradeConfirmationPending?> read(String actor, String kind, String parent) async => value;
  @override Future<void> write(TradeConfirmationPending pending) async {
    if (value != null) throw StateError('existing'); value = pending;
  }
  @override Future<void> clear(TradeConfirmationPending pending) async {
    if (tradeConfirmationJson(value?.toJson()) != tradeConfirmationJson(pending.toJson())) throw StateError('mismatch');
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real synthetic SQL API responses parse into separate local pages and the same approved registered-seal payload', () {
    final sql = jsonDecode(File('test/fixtures/trade_document_confirmation_api_synthetic.json').readAsStringSync()) as Map;
    expect(sql['synthetic_fixture'], true);
    final issued = Map<String, dynamic>.from(sql['issued_workspace'] as Map);
    final workspace = TradeConfirmationWorkspace.parse(issued, kind: issued['kind'] as String,
      parentId: issued['parent_id'] as String, sourceRevision: issued['source_revision'] as String,
      actorId: issued['actor_id'] as String);
    final preview = TradeConfirmationPreview.parse(sql['issued_preview'], workspace);
    final response = sql['confirmation'] as Map;
    final command = TradeConfirmationCommand(expected: preview.expected, requestId: response['request_id'] as String);
    expect(TradeConfirmationResult.parse(response, command).value['operation'], 'monthly_content_review_with_seal');
    final invoice = TradeConfirmationCommand(expected: TradeConfirmationDescriptor.parse(sql['invoice_expected_command']),
      requestId: (sql['invoice_confirmation'] as Map)['request_id'] as String);
    expect(TradeConfirmationResult.parse(sql['invoice_confirmation'], invoice).value['operation'], 'invoice_final_approval_with_seal');
    final ordinaryRaw = sql['ordinary_assigned_workspace'] as Map;
    final ordinary = TradeConfirmationWorkspace.parse(ordinaryRaw, kind: 'invoice',
      parentId: ordinaryRaw['parent_id'] as String,
      sourceRevision: DateTime.parse(ordinaryRaw['source_revision'] as String).toUtc().toIso8601String(),
      actorId: ordinaryRaw['actor_id'] as String);
    expect(ordinary.integrationRequired, false);
    expect(ordinary.canConfirm, false);
    expect(ordinary.value['local_document_id'], isNull);
    expect(ordinary.unavailableReason, 'ordinary_assigned_approval');
    expect(() => TradeConfirmationPreview.parse(sql['issued_preview'], ordinary), throwsFormatException);
    final received = sql['received_workspace'] as Map;
    expect(received['local_document_id'], isNot(issued['local_document_id']));
    expect(received['document_id'], issued['document_id']);
    Map<String, dynamic> scope(Map w) => tradeConfirmationRenderScope(w);
    final ownAttachment = TradeConfirmationPdf.approvedAttachment(Map<String, dynamic>.from(sql['issued_render'] as Map),
      scope(issued), issued['actor_id'] as String);
    final peerAttachment = TradeConfirmationPdf.approvedAttachment(Map<String, dynamic>.from(sql['received_render'] as Map),
      scope(received), received['actor_id'] as String);
    expect(peerAttachment.payload, ownAttachment.payload);
    final ownScope = scope(issued);
    expect(() => ownScope['expected_document_id'] = parent, throwsUnsupportedError);
    final wrongDocument = Map<String, dynamic>.from(sql['issued_render'] as Map)..['document_id'] = parent;
    expect(() => TradeConfirmationPdf.approvedAttachment(wrongDocument, ownScope, issued['actor_id'] as String), throwsFormatException);
    expect((ownAttachment.payload['company_seal_snapshot'] as Map)['style'], 'uploaded_png');
    expect((ownAttachment.payload['company_seal_snapshot'] as Map)['png_base64'], isNot(contains('\n')));
    final originalSnapshot = (((sql['issued_render'] as Map)['evidence'] as Map)['seals'] as List).single['seal_snapshot'] as Map;
    expect((ownAttachment.payload['company_seal_snapshot'] as Map)['png_sha256'], originalSnapshot['png_sha256']);
    expect(originalSnapshot['png_base64'], contains('\n'));
    final crlfRender = Map<String, dynamic>.from(jsonDecode(jsonEncode(sql['issued_render'])) as Map);
    final crlfSnapshot = (((crlfRender['evidence'] as Map)['seals'] as List).single as Map)['seal_snapshot'] as Map;
    crlfSnapshot['png_base64'] = (crlfSnapshot['png_base64'] as String).replaceAll('\n', '\r\n');
    expect(crlfSnapshot['png_base64'], contains('\r\n'));
    final crlfAttachment = TradeConfirmationPdf.approvedAttachment(crlfRender, scope(issued), issued['actor_id'] as String);
    expect(crlfAttachment.payload, ownAttachment.payload);
    expect((crlfAttachment.payload['company_seal_snapshot'] as Map)['png_sha256'], originalSnapshot['png_sha256']);
    final journal = tradeConfirmationJson(TradeConfirmationPending(command).toJson());
    expect(journal.contains('png_base64'), false);
    expect(journal.contains('snapshot'), false);
  });
  for (final mode in ['cap_absent', 'not_integrated', 'transport', 'unknown_pending']) {
    testWidgets('existing approval fallback is limited to known unavailable or non-integrated scope: $mode', (tester) async {
      final repository = FakeRepository()..capability = mode != 'cap_absent' && mode != 'unknown_pending';
      addTearDown(repository.changes.close);
      if (mode == 'transport') repository.capabilityError = StateError('transport');
      final store = MemoryStore();
      if (mode == 'unknown_pending') {
        store.value = TradeConfirmationPending(TradeConfirmationCommand(
          expected: TradeConfirmationDescriptor.parse(descriptor()), requestId: TradeConfirmationCommand.newRequestId()));
      }
      TradeConfirmationFlowOutcome? outcome;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () async { outcome = await Navigator.of(context).push<TradeConfirmationFlowOutcome>(MaterialPageRoute(builder: (_) =>
          TradeDocumentConfirmationPage(kind: 'invoice', parentId: parent, sourceRevision: '2026-10-22T00:00:00Z',
            repository: repository, pendingStore: store))); }, child: const Text('open'))))));
      await tester.tap(find.text('open')); await tester.pumpAndSettle();
      if (mode == 'cap_absent' || mode == 'not_integrated') {
        expect(outcome, TradeConfirmationFlowOutcome.legacy);
      } else {
        expect(outcome, isNull);
        expect(find.byType(TradeDocumentConfirmationPage), findsOneWidget);
      }
      expect(repository.confirms, 0);
      if (mode == 'unknown_pending') expect(store.value, isNotNull);
    });
  }
  test('approved renderer rejects actor, company, local page and revision mismatches before loading fonts or assets', () {
    final scope = {'p_company_id': company, 'p_local_document_id': local,
      'p_document_revision': 1, 'p_kind': 'invoice', 'expected_document_id': document};
    final raw = {'contract_version': 1, 'kind': 'invoice', 'company_id': company, 'actor_id': actor,
      'local_document_id': local, 'document_id': document, 'document_revision': 1,
      'side': 'issued', 'archive': false, 'evidence': <String, dynamic>{}};
    for (final replacement in <String, Object>{'actor_id': company, 'company_id': actor,
        'local_document_id': parent, 'document_revision': 2}.entries) {
      expect(() => TradeConfirmationPdf.approved({...raw, replacement.key: replacement.value}, scope, actor), throwsFormatException);
    }
    expect(() => TradeConfirmationPdf.approved({...raw, 'archive': true}, scope, actor), throwsFormatException);
  });
  test('exact approved descriptor is immutable, separate local identity and journal never retain PNG or credentials', () {
    final raw = descriptor(); final parsed = TradeConfirmationDescriptor.parse(raw);
    raw['document_id'] = parent;
    expect(parsed.documentId, document);
    expect(() => parsed.value['document_id'] = parent, throwsUnsupportedError);
    expect(() => TradeConfirmationDescriptor.parse({...descriptor(), 'local_document_id': document}), throwsFormatException);
    expect(() => TradeConfirmationDescriptor.parse({...descriptor(), 'contract_version': 1.0}), throwsFormatException);
    for (final key in ['png_base64', 'access_token', 'display_preview']) {
      expect(() => TradeConfirmationDescriptor.parse({...descriptor(), key: 'not-allowed'}), throwsFormatException);
    }
    final command = TradeConfirmationCommand(expected: parsed, requestId: TradeConfirmationCommand.newRequestId());
    expect(command.params.keys.toSet(), {'p_expected_command', 'p_request_id', 'p_document_confirmed', 'p_seal_confirmed'});
    expect(command.receiptParams['p_expected_command'], parsed.value);
    expect(jsonEncode(TradeConfirmationPending(command).toJson()).contains('fixture-session'), false);
  });
  test('invoice ISO source revision matches the same server timestamp while preserving server canonical text', () {
    final raw = {'contract_version': 1, 'kind': 'invoice', 'company_id': company, 'actor_id': actor,
      'parent_id': parent, 'source_revision': '2026-10-22 13:18:31.745+00', 'side': 'issued',
      'integration_required': false, 'can_integrated_confirm': false, 'can_render': false, 'unavailable_reason': null};
    final parsed = TradeConfirmationWorkspace.parse(raw, kind: 'invoice', parentId: parent,
      sourceRevision: '2026-10-22T13:18:31.745Z', actorId: actor);
    expect(parsed.sourceRevision, raw['source_revision']);
    expect(() => TradeConfirmationWorkspace.parse(raw, kind: 'invoice', parentId: parent,
      sourceRevision: '2026-10-22T13:18:31.746Z', actorId: actor), throwsFormatException);
  });
  test('invoice and monthly results cannot claim another operation or financial finalization', () {
    for (final kind in ['invoice', 'payment_certificate']) {
      final command = TradeConfirmationCommand(expected: TradeConfirmationDescriptor.parse(descriptor(kind: kind)),
        requestId: TradeConfirmationCommand.newRequestId());
      expect(TradeConfirmationResult.parse(result(command), command).value['kind'], kind);
      expect(() => TradeConfirmationResult.parse({...result(command), 'actor_id': company}, command), throwsFormatException);
      final wrong = result(command);
      (wrong['result'] as Map)[kind == 'invoice' ? 'financial_approved' : 'financial_finalized'] = kind != 'invoice';
      expect(() => TradeConfirmationResult.parse(wrong, command), throwsFormatException);
    }
  });
  test('unknown commit survives recreation; receipt denial or absence never republishes or clears the original request', () async {
    final root = await Directory.systemTemp.createTemp('trade-confirmation-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FakeRepository()..error = StateError('unknown transport');
    addTearDown(repository.changes.close);
    FileTradeConfirmationPendingStore store() => FileTradeConfirmationPendingStore(currentActor: () => repository.actorId, directory: () async => root);
    TradeConfirmationController controller() => TradeConfirmationController(repository: repository, store: store(), kind: 'invoice', parentId: parent);
    final first = controller(); await first.load();
    repository.beforeConfirm = (command) async => expect((await store().read(actor, 'invoice', parent))!.command.params, command.params);
    await expectLater(first.confirm(TradeConfirmationDescriptor.parse(descriptor())), throwsStateError);
    final original = first.pending!.command;
    final restored = controller(); await restored.load();
    expect(restored.pending!.command.params, original.params);
    expect(await restored.lookup(), isNull);
    expect(restored.pending, isNotNull);
    repository.receiptError = const PostgrestException(message: 'denied', code: '42501');
    await expectLater(restored.lookup(), throwsA(isA<PostgrestException>()));
    expect(await store().read(actor, 'invoice', parent), isNotNull);
    await expectLater(restored.confirm(TradeConfirmationDescriptor.parse(descriptor())), throwsStateError);
    repository..receiptError = null..found = true;
    expect(await restored.lookup(), isNotNull);
    expect(await store().read(actor, 'invoice', parent), isNull);
    expect(repository.confirms, 1);
  });
  test('known first-attempt rollback clears only its exact request; different session retains unknown evidence', () async {
    final root = await Directory.systemTemp.createTemp('trade-confirmation-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final repository = FakeRepository()..error = const PostgrestException(message: 'stale', code: '40001');
    addTearDown(repository.changes.close);
    final store = FileTradeConfirmationPendingStore(currentActor: () => repository.actorId, directory: () async => root);
    final controller = TradeConfirmationController(repository: repository, store: store, kind: 'invoice', parentId: parent);
    await controller.load();
    await expectLater(controller.confirm(TradeConfirmationDescriptor.parse(descriptor())), throwsA(isA<PostgrestException>()));
    expect(controller.pending, isNull);
    repository..error = StateError('transport')..beforeConfirm = (_) async { repository.token = 'different-session'; };
    await expectLater(controller.confirm(TradeConfirmationDescriptor.parse(descriptor())), throwsStateError);
    expect(await store.read(actor, 'invoice', parent), isNotNull);
    await expectLater(controller.lookup(), throwsStateError);
  });
  for (final mode in ['supported', 'missing', 'permission', 'transport', 'wrong_type']) {
    test('SDK capability distinguishes absent API from transport and permission failure: $mode', () async {
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id':'90000000-0000-4000-8000-000000000001','role':'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.${base64Url.encode(List<int>.filled(32,7)).replaceAll('=','')}';
      var calls = 0;
      final client = SupabaseClient('https://fixture.invalid', 'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
          if (request.url.path == '/auth/v1/token') {
            return http.Response(jsonEncode({'access_token': token, 'refresh_token': 'fixture', 'token_type': 'bearer',
              'expires_in': 3600, 'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
                'email': 'fixture@example.invalid', 'created_at': '2026-01-01T00:00:00Z',
                'app_metadata': {}, 'user_metadata': {}}}), 200, headers: {'content-type': 'application/json'}, request: request);
          }
          calls++;
          expect(request.url.path, '/rest/v1/rpc/trade_document_confirmation_contract_version');
          expect(request.headers.entries.where((e) => e.key.toLowerCase() == 'authorization').single.value, 'Bearer $token');
          if (mode == 'transport') throw StateError('fixture transport');
          if (mode == 'missing' || mode == 'permission') {
            return http.Response(jsonEncode({'code': mode == 'missing' ? 'PGRST202' : '42501', 'message': 'fixture unavailable'}),
              mode == 'missing' ? 404 : 403, headers: {'content-type': 'application/json'}, request: request);
          }
          return http.Response(jsonEncode(mode == 'wrong_type' ? '1' : 1), 200,
            headers: {'content-type': 'application/json'}, request: request);
        }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
      final repository = SupabaseTradeConfirmationRepository(client);
      addTearDown(repository.dispose);
      if (mode == 'supported' || mode == 'missing') {
        expect(await repository.available(), mode == 'supported');
      } else if (mode == 'permission') {
        await expectLater(repository.available(), throwsA(isA<PostgrestException>()));
      } else if (mode == 'transport') {
        await expectLater(repository.available(), throwsStateError);
      } else { await expectLater(repository.available(), throwsFormatException); }
      expect(calls, 1);
    });
  }
}

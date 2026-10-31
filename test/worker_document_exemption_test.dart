import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_exemption.dart';
import 'package:sk_works/features/people/worker_document_page.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';
import 'package:sk_works/features/shared/resource_registration_card.dart';

class _Repository extends WorkerDocumentRepository {
  _Repository(super.client) : super.forTesting();
  bool manager = true;
  bool enabled = true;
  String actor = 'admin';
  int writes = 0;
  Map<String, dynamic>? exemption;
  bool bankFixture = false;
  final status = <String, dynamic>{'id': 'saved', 'worker_id': 'worker',
    'requirement_id': 'requirement', 'status': 'submitted',
    'attachment_path': 'retained/original.pdf'};
  @override
  String? get actorId => actor;
  @override
  bool get exemptionEditingAvailable => enabled;
  @override
  Future<bool> canManageRequirements() async => manager;
  @override
  Future<bool> canManageStatuses() async => manager;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll({bool includeHiddenRequirements = false}) async => {
    'workers': [{'id': 'worker', 'company_id': 'company', 'name': '対象社員', 'status': 'active'}],
    'requirements': [{'id': 'requirement', 'name': bankFixture ? '銀行口座情報' : '本人書類', 'scope': 'internal',
      'is_required': true, 'is_active': true, 'expiry_required': false}],
    'bank_account_metadata': [if (bankFixture) {'worker_id': 'worker', 'company_id': 'company', 'updated_at': '2026-10-31T00:00:00Z'}],
    'statuses': [if (!bankFixture) Map.of(status)], 'exemptions': [if (exemption != null) Map.of(exemption!)],
  };
  @override
  Future<void> setDocumentExemption({required String workerId, required String requirementId,
    required bool active, required int expectedVersion, required String reason}) async {
    expect(workerId, 'worker'); expect(requirementId, 'requirement');
    expect(expectedVersion, exemption?['version'] ?? 0);
    expect(reason.trim(), isNotEmpty);
    writes++;
    exemption = {'worker_id': workerId, 'requirement_id': requirementId,
      'active': active, 'version': expectedVersion + 1, 'reason': reason};
  }
}

void main() {
  test('setup exemption is not a submitted document; revoke restores original evidence', () {
    final docs = <String, dynamic>{'worker_id': 'worker',
      'requirements': [{'id': 'requirement', 'name': '本人書類', 'is_active': true, 'is_required': true}],
      'statuses': <Map<String, dynamic>>[],
      'exemptions': [{'worker_id': 'worker', 'requirement_id': 'requirement', 'active': true,
        'version': 1, 'reason': '管理者確認'}]};
    var rows = TutorialEvidenceRepository.documentCheckpoints(docs, today: DateTime(2026, 10, 27));
    expect(rows.single.state, TutorialEvidenceState.notApplicable);
    expect(rows.single.label, '本人書類（提出免除）');
    expect(rows.single.evidenceKey, 'exemption:requirement:1');
    (docs['exemptions'] as List).single['active'] = false;
    rows = TutorialEvidenceRepository.documentCheckpoints(docs, today: DateTime(2026, 10, 27));
    expect(rows.single.state, TutorialEvidenceState.missing);
    expect(docs['statuses'], isEmpty);
  });
  test('other worker, duplicate and unverified rows cannot exempt this document', () {
    final row = <String, dynamic>{'worker_id': 'other', 'requirement_id': 'requirement',
      'active': true, 'version': 1, 'reason': '確認'};
    expect(documentExemptionFor([row], 'worker', 'requirement'), isNull);
    row['worker_id'] = 'worker';
    expect(documentExemptionFor([row, row], 'worker', 'requirement'), isNull);
    row['version'] = '1';
    expect(documentExemptionFor([row], 'worker', 'requirement'), isNull);
  });
  late SupabaseClient client;
  late _Repository repo;
  setUp(() {
    client = SupabaseClient('https://synthetic.invalid', 'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    repo = _Repository(client);
  });
  tearDown(() async => client.dispose());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: WorkerDocumentPage(
      view: WorkerDocumentView.workers, repositoryOverride: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('対象社員'));
    await tester.pumpAndSettle();
  }
  testWidgets('manager exempts one employee with reason and can revoke; saved document stays', (tester) async {
    final retained = Map.of(repo.status);
    await open(tester);
    final button = find.text('この社員の提出を免除');
    await tester.ensureVisible(button); await tester.pumpAndSettle(); await tester.tap(button); await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '免除を保存'));
    await tester.pumpAndSettle(); expect(repo.writes, 0);
    await tester.enterText(find.byType(TextField).last, '本人の事情を確認');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '免除を保存'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1); expect(find.text('提出免除'), findsOneWidget);
    expect(find.textContaining('未確認'), findsNothing);
    final exemptCard = tester.widget<ResourceRegistrationCard>(find.byKey(
      const ValueKey('managed-document:admin:worker:requirement')));
    expect(exemptCard.detailLabel, isNot(contains('提出済み')));
    expect(exemptCard.detailLabel, contains('本人の事情を確認'));
    expect(repo.status, retained);
    await tester.ensureVisible(find.text('免除を解除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('免除を解除')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '提出対象へ戻す');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '免除を解除'));
    await tester.pumpAndSettle();
    expect(repo.writes, 2); expect(repo.exemption!['active'], false);
    expect(repo.status, retained); expect(find.text('提出免除'), findsNothing);
  });
  testWidgets('submitted required document without attachment stays incomplete in managed view', (tester) async {
    repo.status.remove('attachment_path');
    await open(tester);
    final card = tester.widget<ResourceRegistrationCard>(find.byKey(
      const ValueKey('managed-document:admin:worker:requirement')));
    expect(card.statusLabel, '添付待ち');
    expect(card.registered, false);
    expect(card.onAction, isNotNull);
    expect(repo.status['status'], 'submitted');
    expect(repo.writes, 0);
  });
  testWidgets('private bank metadata completes managed card without a mirrored document status', (tester) async {
    repo.bankFixture = true;
    await open(tester);
    final card = tester.widget<ResourceRegistrationCard>(find.byKey(
      const ValueKey('managed-document:admin:worker:requirement')));
    expect(card.statusLabel, '登録済み');
    expect(card.registered, true);
    expect(find.text('完了 1/1'), findsOneWidget);
    expect(repo.writes, 0);
  });
  testWidgets('worker role and disabled backend do not offer exemption action', (tester) async {
    repo.manager = false;
    await open(tester);
    expect(find.text('この社員の提出を免除'), findsNothing);
    repo.manager = true; repo.enabled = false;
    await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
    await open(tester);
    expect(find.text('この社員の提出を免除'), findsNothing);
  });
}

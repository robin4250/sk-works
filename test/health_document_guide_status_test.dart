import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';
import 'package:sk_works/features/tutorial/tutorial_page.dart';
import 'package:sk_works/features/tutorial/tutorial_preferences.dart';
import 'package:sk_works/features/tutorial/tutorial_workspace.dart';

// Synthetic metadata only: no diagnosis, document contents or real object path.
const _worker = 'synthetic-worker', _requirement = 'synthetic-health-requirement';
final _today = DateTime(2026, 10, 29);
Map<String, dynamic> _documents({String? expiry, bool attachment = true,
    String worker = _worker, bool exemption = false, String status = 'submitted'}) => {
  'worker_id': _worker,
  'requirements': [
    {'id': _requirement, 'name': '健康診断書', 'is_active': true,
      'is_required': true, 'expiry_required': true},
  ],
  'statuses': [
    {'id': 'synthetic-status', 'worker_id': worker, 'requirement_id': _requirement,
      'status': status, 'expires_at': expiry,
      'attachment_path': attachment ? 'synthetic/retained-object' : null},
  ],
  'exemptions': [if (exemption)
    {'worker_id': _worker, 'requirement_id': _requirement,
      'active': true, 'version': 1, 'reason': 'synthetic administrative reason'},
  ],
};
TutorialEvidenceSnapshot _snapshot(Map<String, dynamic> documents) =>
  TutorialEvidenceSnapshot(role: 'employee', tasks: [
    TutorialEvidenceTask(key: 'required_documents', actionKey: 'document_register',
      checkpoints: TutorialEvidenceRepository.documentCheckpoints(documents, today: _today)),
  ]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final status in ['submitted', 'verified']) {
  for (final example in [
    (expiry: null, label: '登録済み・期限未入力', state: TutorialEvidenceState.missing),
    (expiry: '2026-10-28', label: '登録済み・期限切れ', state: TutorialEvidenceState.missing),
    (expiry: 'invalid-date', label: '登録済み・期限を確認', state: TutorialEvidenceState.unknown),
    (expiry: '2026-02-30', label: '登録済み・期限を確認', state: TutorialEvidenceState.unknown),
  ]) {
    testWidgets('saved $status health attachment shows ${example.label} without completing preparation', (tester) async {
      final data = _documents(expiry: example.expiry, status: status);
      final snapshot = _snapshot(data);
      final checkpoint = snapshot.tasks.single.checkpoints.single;
      expect(checkpoint.state, example.state);
      expect(checkpoint.evidenceKey, 'synthetic-status:status');
      final progress = TutorialWorkspace.fromSnapshot(snapshot);
      expect(progress.progress.required.total, 1, reason: 'incomplete health evidence remains in the denominator');
      expect(progress.progress.required.completed, 0);
      expect(progress.canCompleteInitial, isFalse);
      final preferences = TutorialPreferences();
      await tester.pumpWidget(MaterialApp(home: TutorialPage(
        userId: 'synthetic-user', companyId: 'synthetic-company',
        availableActionKeys: const {'document_register'}, preferences: preferences,
        onOpenAction: (_) async {}, loadSnapshot: (_) async => snapshot)));
      await tester.pumpAndSettle();
      expect(find.text('健康診断書'), findsOneWidget);
      // This assertion compiles on the old source and exposes the incorrect
      // generic missing label; it does not reference the new statusLabel API.
      expect(find.text(example.label), findsOneWidget);
      expect(find.text('未登録'), findsNothing);
      expect(await preferences.initialCompleted(userId: 'synthetic-user', companyId: 'synthetic-company'), isFalse);
      expect((data['statuses'] as List).single['expires_at'], example.expiry);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  }

  test('valid date boundary remains saved while foreign-worker and missing-attachment evidence do not', () {
    for (final expiry in ['2026-10-29', '2026-10-30']) {
      final workspace = TutorialWorkspace.fromSnapshot(_snapshot(_documents(expiry: expiry)));
      expect(workspace.progress.required.total, 1);
      expect(workspace.progress.required.completed, 1);
      expect(workspace.canCompleteInitial, isTrue);
    }
    for (final data in [
      _documents(expiry: '2026-10-30', worker: 'another-synthetic-worker'),
      _documents(expiry: '2026-10-30', attachment: false),
    ]) {
      final workspace = TutorialWorkspace.fromSnapshot(_snapshot(data));
      expect(workspace.progress.required.total, 1);
      expect(workspace.progress.required.completed, 0);
      expect(workspace.canCompleteInitial, isFalse);
    }
  });

  testWidgets('valid explicit exemption says exemption rather than submitted or generic inapplicable', (tester) async {
    final snapshot = _snapshot(_documents(exemption: true));
    expect(snapshot.tasks.single.checkpoints.single.state, TutorialEvidenceState.notApplicable);
    final workspace = TutorialWorkspace.fromSnapshot(snapshot);
    expect(workspace.progress.required.total, 0);
    expect(workspace.progress.required.completed, 0);
    await tester.pumpWidget(MaterialApp(home: TutorialPage(
      userId: 'synthetic-user', companyId: 'synthetic-company',
      availableActionKeys: const {'document_register'},
      onOpenAction: (_) async {}, loadSnapshot: (_) async => snapshot)));
    await tester.pumpAndSettle();
    expect(find.text('免除'), findsOneWidget);
    expect(find.text('対象外'), findsNothing);
    expect(find.text('登録済み'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

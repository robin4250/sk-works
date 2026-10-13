import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';
import 'package:sk_works/features/tutorial/tutorial_home_card.dart';
import 'package:sk_works/features/tutorial/tutorial_page.dart';
import 'package:sk_works/features/tutorial/tutorial_preferences.dart';
import 'package:sk_works/features/tutorial/tutorial_workspace.dart';

TutorialEvidenceSnapshot snapshot(TutorialEvidenceState state, {bool recommendation = false}) =>
  TutorialEvidenceSnapshot(role: 'admin', tasks: [
    TutorialEvidenceTask(key: 'personal_profile', actionKey: 'profile', checkpoints: [
      TutorialEvidenceCheckpoint('name', state, label: '氏名',
          evidenceKey: state == TutorialEvidenceState.saved ? 'profile:1:name' : null),
    ]),
    if (recommendation) TutorialEvidenceTask(key: 'extra', actionKey: 'profile',
      requiredForCompletion: false, checkpoints: const [
        TutorialEvidenceCheckpoint('optional', TutorialEvidenceState.missing, label: '住所'),
      ]),
  ]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('missing saved evidence ID never becomes completed', () {
    final value = TutorialWorkspace.fromSnapshot(TutorialEvidenceSnapshot(role: 'admin', tasks: [
      TutorialEvidenceTask(key: 'personal_profile', actionKey: 'profile', checkpoints: const [
        TutorialEvidenceCheckpoint('name', TutorialEvidenceState.saved, label: '氏名'),
      ]),
    ]));
    expect(value.canCompleteInitial, isFalse);
    expect(value.progress.required.percentage, isNull);
  });

  test('unknown membership never clears the initial guide', () {
    final saved = snapshot(TutorialEvidenceState.saved);
    final value = TutorialWorkspace.fromSnapshot(TutorialEvidenceSnapshot(role: null, tasks: saved.tasks));
    expect(value.canCompleteInitial, isFalse);
    expect(value.progress.required.percentage, isNull);
  });

  test('completion flags are scoped and collision-safe', () async {
    final prefs = TutorialPreferences();
    await prefs.markInitialCompleted(userId: 'a.b', companyId: 'c');
    expect(await prefs.initialCompleted(userId: 'a.b', companyId: 'c'), isTrue);
    expect(await prefs.initialCompleted(userId: 'a', companyId: 'b.c'), isFalse);
    expect(await prefs.initialCompleted(userId: 'other', companyId: 'c'), isFalse);
  });

  testWidgets('unknown home evidence shows unconfirmed status, never zero percent', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TutorialHomeCard(
      userId: 'u', companyId: 'c', availableActionKeys: const {'profile'},
      onOpenAction: (_) async {}, loadSnapshot: (_) async => snapshot(TutorialEvidenceState.unknown),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('準備状況：未確定'), findsOneWidget);
    expect(find.textContaining('準備 0%'), findsNothing);
  });

  testWidgets('required completion hides home even when recommended items remain', (tester) async {
    final prefs = TutorialPreferences();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TutorialHomeCard(
      userId: 'u', companyId: 'c', availableActionKeys: const {'profile'},
      preferences: prefs, onOpenAction: (_) async {},
      loadSnapshot: (_) async => snapshot(TutorialEvidenceState.saved, recommendation: true),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('SKOの初期準備'), findsNothing);
    expect(await prefs.initialCompleted(userId: 'u', companyId: 'c'), isTrue);
  });

  testWidgets('adding later tasks cannot resurrect an already cleared initial card', (tester) async {
    final prefs = TutorialPreferences();
    await prefs.markInitialCompleted(userId: 'u', companyId: 'c');
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TutorialHomeCard(
      userId: 'u', companyId: 'c', availableActionKeys: const {'profile', 'document_register'},
      preferences: prefs, refreshToken: 2, onOpenAction: (_) async {},
      loadSnapshot: (_) async { reads++; return snapshot(TutorialEvidenceState.missing); },
    ))));
    await tester.pumpAndSettle();
    expect(find.text('SKOの初期準備'), findsNothing);
    expect(reads, 0);
  });

  testWidgets('manual guide restart keeps evidence and cleared flag intact', (tester) async {
    final prefs = TutorialPreferences();
    await prefs.markInitialCompleted(userId: 'u', companyId: 'c');
    await tester.pumpWidget(MaterialApp(home: TutorialPage(
      userId: 'u', companyId: 'c', availableActionKeys: const {'profile'},
      preferences: prefs, onOpenAction: (_) async {},
      loadSnapshot: (_) async => snapshot(TutorialEvidenceState.saved),
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('案内を初めから'));
    await tester.tap(find.text('案内を初めから'));
    await tester.pumpAndSettle();
    expect(find.textContaining('準備 100% / 残り 0%'), findsOneWidget);
    expect(await prefs.initialCompleted(userId: 'u', companyId: 'c'), isTrue);
  });
}

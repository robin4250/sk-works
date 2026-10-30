import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';
import 'package:sk_works/features/tutorial/tutorial_home_card.dart';
import 'package:sk_works/features/tutorial/tutorial_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const originalId = '11111111-1111-4111-8111-111111111111';
  const addedId = '22222222-2222-4222-8222-222222222222';
  const addedName = '会社で追加した必須書類';

  Map<String, dynamic> requirement(String id, String name) => {
    'id': id, 'name': name, 'is_active': true, 'is_required': true,
    'expiry_required': false,
  };

  TutorialEvidenceSnapshot documents(List<Map<String, dynamic>> requirements) =>
      TutorialEvidenceSnapshot(role: 'admin', tasks: [
        TutorialEvidenceTask(
          key: 'required_documents',
          actionKey: 'document_register',
          checkpoints: TutorialEvidenceRepository.documentCheckpoints({
            'worker_id': 'worker',
            'company_id': 'company',
            'requirements': requirements,
            'statuses': [
              {
                'id': 'saved-original', 'worker_id': 'worker',
                'requirement_id': originalId, 'status': 'verified',
                'attachment_path': 'private/original', 'expires_at': null,
              },
            ],
          }, today: DateTime(2026, 10, 30)),
        ),
      ]);

  testWidgets('new custom requirement revives completed home after route refresh',
      (tester) async {
    final requirements = [requirement(originalId, '以前の書類')];
    var reads = 0;
    Widget home(int token) => MaterialApp(home: Scaffold(body: TutorialHomeCard(
      userId: 'user', companyId: 'company',
      availableActionKeys: const {'document_register'},
      refreshToken: token, onOpenAction: (_) async {},
      loadSnapshot: (_) async { reads++; return documents(requirements); },
    )));
    await tester.pumpWidget(home(0));
    await tester.pumpAndSettle();
    expect(find.text('SKOの初期準備'), findsNothing);

    requirements.add(requirement(addedId, addedName));
    await tester.pumpWidget(home(1));
    await tester.pumpAndSettle();
    expect(find.text('SKOの初期準備'), findsOneWidget);
    expect(reads, 2);
    final checkpoints = documents(requirements).tasks.single.checkpoints;
    expect(checkpoints.last.key, 'document:$addedId');
    expect(checkpoints.last.state, TutorialEvidenceState.missing);
  });

  testWidgets('guide action return displays requirement added after initial load',
      (tester) async {
    final requirements = [requirement(originalId, '以前の書類')];
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: TutorialPage(
      userId: 'user', companyId: 'company',
      availableActionKeys: const {'document_register'},
      onOpenAction: (key) async {
        expect(key, 'document_register');
        requirements.add(requirement(addedId, addedName));
      },
      loadSnapshot: (_) async { reads++; return documents(requirements); },
    )));
    await tester.pumpAndSettle();
    expect(find.text(addedName), findsNothing);
    final open = find.text('登録画面を開き直す');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text(addedName), findsOneWidget);
    expect(reads, 2);
    expect(find.text('登録画面を開く'), findsOneWidget);
  });
}

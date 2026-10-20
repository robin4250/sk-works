import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/home/employee_resources_page.dart';
import 'package:sk_works/features/payroll/payroll_review_page.dart';
import 'package:sk_works/features/people/worker_document_page.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

// UI fixtures must not initialize network clients or background JSON isolates.
// The separate HTTP test exercises the real client and scoped repository writes.
class UnusedFixtureClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected client access in UI fixture');
}

class DocumentFixture extends WorkerDocumentRepository {
  DocumentFixture() : super.forTesting(UnusedFixtureClient());
  final removed = <String>[];
  @override
  String get actorId => 'actor';
  @override
  Future<bool> canManageRequirements() async => true;
  @override
  Future<bool> canManageStatuses() async => true;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll({bool includeHiddenRequirements = false}) async => {
    'workers': [
      {'id': 'worker', 'name': '社員A'},
    ],
    'requirements': [
      if (includeHiddenRequirements || !removed.contains('internal'))
        {'id': 'internal', 'name': '社内書類', 'scope': 'internal', 'is_active': !removed.contains('internal')},
      if (includeHiddenRequirements || !removed.contains('upstream'))
        {'id': 'upstream', 'name': '取引先書類', 'scope': 'upstream', 'is_active': !removed.contains('upstream')},
    ],
    'statuses': [
      {
        'worker_id': 'worker',
        'requirement_id': 'internal',
        'status': 'submitted',
      },
    ],
  };
  @override
  Future<void> setRequirementVisible(String id, bool visible) async {
    if (visible) {
      removed.remove(id);
    } else {
      removed.add(id);
    }
  }
}

void main() {
  testWidgets('payroll settings entry survives unavailable review data', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(home: PayrollReviewPage(onOpenSettings: () => opened = true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payroll-individual-settings-entry')));
    expect(opened, isTrue);
  });
  testWidgets(
    'resources exposes permitted children only and opens their existing actions',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: EmployeeResourcesPage(
            availableKeys: {'people', 'documents'},
            onOpen: (key) async {
              opened.add(key);
            },
          ),
        ),
      );
      expect(find.text('社員データ'), findsOneWidget);
      expect(find.text('従業員資格'), findsNothing);
      await tester.tap(find.text('必要書類'));
      expect(opened, ['documents']);
    },
  );
  testWidgets(
    'documents separates employee search from settings and does not select an employee automatically',
    (tester) async {
      final repo = DocumentFixture();
      await tester.pumpWidget(
        MaterialApp(home: WorkerDocumentPage(repositoryOverride: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('従業員データ編集'), findsOneWidget);
      expect(find.text('必要書類設定'), findsOneWidget);
      await tester.tap(find.text('従業員データ編集'));
      await tester.pumpAndSettle();
      expect(find.text('従業員を検索して選択してください'), findsOneWidget);
      expect(find.text('必要書類の項目を追加'), findsNothing);
      await tester.tap(find.text('社員A'));
      await tester.pumpAndSettle();
      expect(find.text('社内書類'), findsOneWidget);
      expect(find.text('登録する'), findsNothing);
    },
  );
  testWidgets(
    'settings shows selected scope; cancelled removal never changes a requirement',
    (tester) async {
      final repo = DocumentFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkerDocumentPage(
            view: WorkerDocumentView.settings,
            repositoryOverride: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('社内書類'), findsOneWidget);
      expect(find.text('取引先書類'), findsNothing);
      await tester.tap(find.text('取引先'));
      await tester.pumpAndSettle();
      expect(find.text('社内書類'), findsNothing);
      expect(find.text('取引先書類'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('requirement-visible-upstream')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(repo.removed, isEmpty);
      await tester.tap(find.byKey(const ValueKey('requirement-visible-upstream')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('非表示'));
      await tester.pumpAndSettle();
      expect(repo.removed, ['upstream']);
      expect(find.text('取引先書類'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('requirement-visible-upstream'))).value, isFalse);
    },
  );
}

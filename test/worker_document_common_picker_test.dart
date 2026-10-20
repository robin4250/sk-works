import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_page.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

class _Repository extends WorkerDocumentRepository {
  _Repository(super.client) : super.forTesting();
  @override
  String? get actorId => 'actor';
  final row = <String, dynamic>{'id': 'original-id', 'name': '履歴書', 'scope': 'upstream', 'is_required': false, 'expiry_required': true};
  bool includedHidden = false;
  bool visibilityFails = false;
  final visibilityWrites = <bool>[];
  @override
  Future<void> setRequirementVisible(String id, bool visible) async {
    visibilityWrites.add(visible);
    if (visibilityFails) throw StateError('保存できませんでした');
    row['is_active'] = visible;
  }
  Map<String, dynamic>? update;
  var inserts = 0;
  @override
  Future<bool> canManageRequirements() async => true;
  @override
  Future<bool> canManageStatuses() async => true;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll({bool includeHiddenRequirements = false}) async {
    includedHidden = includeHiddenRequirements;
    return {'requirements': [Map.of(row)], 'workers': [], 'statuses': []};
  }
  @override
  Future<void> addRequirement({required String name, required String scope, required bool isRequired, required bool expiryRequired}) async { inserts++; }
  @override
  Future<void> updateRequirement({required String id, required String name, required String scope, required bool isRequired, required bool expiryRequired}) async {
    update = {'id': id, 'name': name, 'scope': scope, 'is_required': isRequired, 'expiry_required': expiryRequired};
    row.addAll(update!);
  }
}

void main() {
  late SupabaseClient client;
  late _Repository repository;
  setUp(() {
    client = SupabaseClient('https://synthetic.invalid', 'fixture', authOptions: const AuthClientOptions(autoRefreshToken: false));
    repository = _Repository(client);
  });
  tearDown(() async => client.dispose());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: WorkerDocumentPage(view: WorkerDocumentView.settings, repositoryOverride: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('必要書類を追加'));
    await tester.pumpAndSettle();
  }
  testWidgets('hidden requirement remains in settings and can be shown again', (tester) async {
    repository.row['scope'] = 'internal';
    repository.row['is_active'] = false;
    await tester.pumpWidget(MaterialApp(home: WorkerDocumentPage(view: WorkerDocumentView.settings, repositoryOverride: repository)));
    await tester.pumpAndSettle();
    expect(repository.includedHidden, isTrue);
    expect(find.text('非表示'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('requirement-visible-original-id'))).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('requirement-visible-original-id')));
    await tester.pumpAndSettle();
    expect(repository.row['is_active'], isFalse);
    await tester.tap(find.widgetWithText(FilledButton, '表示'));
    await tester.pumpAndSettle();
    expect(repository.row['is_active'], isTrue);
    expect(find.text('履歴書'), findsOneWidget);
  });
  testWidgets('visibility checkbox preserves saved value until confirmation and cancellation writes nothing', (tester) async {
    repository.row['scope'] = 'internal';
    repository.row['is_active'] = true;
    await tester.pumpWidget(MaterialApp(home: WorkerDocumentPage(view: WorkerDocumentView.settings, repositoryOverride: repository)));
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const ValueKey('requirement-visible-original-id'));
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(repository.row['is_active'], isTrue);
    expect(repository.visibilityWrites, isEmpty);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(repository.visibilityWrites, isEmpty);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '非表示'));
    await tester.pumpAndSettle();
    expect(repository.visibilityWrites, [false]);
    expect(tester.widget<Checkbox>(checkbox).value, isFalse);
    expect(find.text('履歴書'), findsOneWidget);
    expect(repository.includedHidden, isTrue);
  });
  testWidgets('visibility save failure retains the checked value and allows retry', (tester) async {
    repository.row['scope'] = 'internal';
    repository.row['is_active'] = true;
    repository.visibilityFails = true;
    await tester.pumpWidget(MaterialApp(home: WorkerDocumentPage(view: WorkerDocumentView.settings, repositoryOverride: repository)));
    await tester.pumpAndSettle();
    final checkbox = find.byKey(const ValueKey('requirement-visible-original-id'));
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '非表示'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);
    expect(find.textContaining('保存できませんでした'), findsOneWidget);
    expect(repository.visibilityWrites, [false]);
  });
  testWidgets('existing other-purpose document shares original ID and flags without insert', (tester) async {
    await open(tester);
    await tester.tap(find.text('履歴書'));
    await tester.pumpAndSettle();
    expect(find.text('自社・取引会社で共用'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repository.inserts, 0);
    expect(repository.update, {'id': 'original-id', 'name': '履歴書', 'scope': 'both', 'is_required': false, 'expiry_required': true});
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancel selected document makes no change', (tester) async {
    await open(tester);
    await tester.tap(find.text('履歴書'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repository.update, isNull);
    expect(repository.inserts, 0);
    expect(repository.row['scope'], 'upstream');
  });
  testWidgets('new same-name entry directs user to original rather than duplicate', (tester) async {
    await open(tester);
    await tester.tap(find.text('新しい書類を登録'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '履歴書');
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    expect(find.text('登録済みです。書類一覧から選択してください。'), findsOneWidget);
    expect(repository.inserts, 0);
    expect(repository.update, isNull);
    expect(tester.takeException(), isNull);
  });
}


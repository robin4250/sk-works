import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_page.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

class _Repository extends WorkerDocumentRepository {
  _Repository(SupabaseClient client) : super.forTesting(client);
  @override
  String? get actorId => 'actor';
  final row = <String, dynamic>{'id': 'original-id', 'name': '履歴書', 'scope': 'upstream', 'is_required': false, 'expiry_required': true};
  Map<String, dynamic>? update;
  var inserts = 0;
  @override
  Future<bool> canManageRequirements() async => true;
  @override
  Future<bool> canManageStatuses() async => true;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async => {'requirements': [Map.of(row)], 'workers': [], 'statuses': []};
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

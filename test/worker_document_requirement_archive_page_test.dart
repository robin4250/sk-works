import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/people/worker_document_page.dart';
import 'package:sk_works/features/people/worker_document_repository.dart';

class _Repository extends WorkerDocumentRepository {
  _Repository(super.client) : super.forTesting();
  @override
  String? get actorId => actor;
  String actor = 'manager';
  bool manage = true;
  bool failArchive = false;
  int archives = 0;
  int restores = 0;
  int inserts = 0;
  final row = <String, dynamic>{
    'id': 'original-id', 'company_id': 'company', 'name': '重複書類',
    'scope': 'both', 'is_required': true, 'expiry_required': false,
    'is_active': true, 'archived_at': null,
  };
  @override
  Future<bool> canManageRequirements() async => manage;
  @override
  Future<bool> canManageStatuses() async => manage;
  @override
  Future<Map<String, List<Map<String, dynamic>>>> loadAll({bool includeHiddenRequirements = false}) async => {
    'requirements': row['archived_at'] == null ? [Map.of(row)] : [],
    'retained_requirements': [Map.of(row)], 'workers': [], 'statuses': [],
  };
  @override
  Future<void> archiveRequirement(Map<String, dynamic> value) async {
    if (failArchive) throw StateError('書類項目が更新されています');
    archives++;
    row.addAll({'archived_at': '2026-10-21T00:00:00Z', 'is_active': false});
  }
  @override
  Future<void> restoreRequirement(Map<String, dynamic> value) async {
    restores++;
    row.addAll({'archived_at': null, 'is_active': false});
  }
  @override
  Future<void> addRequirement({required String name, required String scope,
    required bool isRequired, required bool expiryRequired}) async { inserts++; }
}

void main() {
  late SupabaseClient client;
  late _Repository repo;
  setUp(() {
    client = SupabaseClient('https://synthetic.invalid', 'fixture',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    repo = _Repository(client);
  });
  tearDown(() async { await client.dispose(); });
  Future<void> open(WidgetTester tester, {bool large = false}) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(large ? 1.3 : 1),
          viewInsets: EdgeInsets.only(bottom: large ? 180 : 0)),
        child: child!),
      home: WorkerDocumentPage(view: WorkerDocumentView.settings,
        repositoryOverride: repo),
    ));
    await tester.pumpAndSettle();
  }
  testWidgets('delete confirms both destinations and hides only the item; restore keeps ID hidden', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('書類項目を削除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('社内・取引先の両方'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();
    expect(repo.archives, 1);
    expect(find.text('重複書類'), findsNothing);
    await tester.tap(find.text('必要書類を追加'));
    await tester.pumpAndSettle();
    expect(find.text('重複書類'), findsNothing);
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除済みの項目（1件）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '復元'));
    await tester.pumpAndSettle();
    expect(find.textContaining('元の登録ID'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '復元'));
    await tester.pumpAndSettle();
    expect(repo.restores, 1);
    expect(repo.row['id'], 'original-id');
    expect(find.text('非表示'), findsOneWidget);
  });
  testWidgets('cancel and CAS failure preserve item and checkbox', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('書類項目を削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(repo.archives, 0);
    repo.failArchive = true;
    await tester.tap(find.byTooltip('書類項目を削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '削除'));
    await tester.pumpAndSettle();
    expect(find.text('重複書類'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, true);
    expect(repo.archives, 0);
  });
  testWidgets('old backend has disabled archive while existing visibility stays available', (tester) async {
    repo.row.remove('archived_at');
    await open(tester);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
        widget is IconButton && widget.tooltip == '項目削除は準備中です')).onPressed, isNull);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNotNull);
  });
  testWidgets('new document dialogs use 320px screen and remain operable above keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, large: true);
    await tester.tap(find.text('必要書類を追加'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AlertDialog)).width, greaterThanOrEqualTo(288));
    await tester.tap(find.text('新しい書類を登録'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AlertDialog)).width, greaterThanOrEqualTo(288));
    await tester.enterText(find.byType(TextField).last, '新規書類');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '追加'));
    await tester.tap(find.widgetWithText(FilledButton, '追加'));
    await tester.pumpAndSettle();
    expect(repo.inserts, 1);
    expect(tester.takeException(), isNull);
  });
}

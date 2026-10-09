import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/company_allowance_identity_repository.dart';
import 'package:sk_works/features/settings/company_allowance_identity_helper.dart';
import 'package:sk_works/features/settings/company_allowance_identity_page.dart';

const company = 'company';
const actor = 'actor';
const itemId = '10000000-0000-0000-0000-000000000001';
List<CompanyAllowanceSlot> slots() => const [
  CompanyAllowanceSlot(slot: 1, name: '現行手当', unit: '回', amountYen: 700),
  CompanyAllowanceSlot(slot: 2, name: null, unit: '日', amountYen: 50),
  CompanyAllowanceSlot(slot: 3, name: null, unit: '回', amountYen: 0),
];
Map<String, dynamic> allowanceHistoryEntry(List<CompanyAllowanceSlot> target, int version, {bool adoption = false, String who = actor}) => {
  'company_id': company, 'version': version, 'actor_id': who, 'changed_at': '2026-10-10T00:00:00Z',
  'event': adoption ? 'adopt' : 'settings_update',
  'after_value': [for (final s in target.where((s) => s.active)) {...s.toJson(), 'id': itemId, 'generation': 1}],
};
CompanyAllowanceIdentityData data({bool adopted = false, int version = 0, List<CompanyAllowanceSlot>? values,
  List<Map<String, dynamic>> events = const []}) => CompanyAllowanceIdentityData(
  companyId: company, version: version, adopted: adopted, slots: values ?? slots(),
  items: adopted ? [for (final s in (values ?? slots()).where((s) => s.active)) {...s.toJson(), 'id': itemId, 'generation': 1}] : [], history: events);

class MemoryStore implements CompanyAllowanceIdentityPendingStore {
  CompanyAllowanceIdentityPending? pending;
  @override
  String actorId() => actor;
  @override
  Future<CompanyAllowanceIdentityPending?> read(String companyId) async => pending;
  @override
  Future<void> write(CompanyAllowanceIdentityPending value) async {
    if (pending != null) {
      throw StateError('existing journal');
    }
    pending = value;
  }
  @override
  Future<void> clear(CompanyAllowanceIdentityPending value) async {
    expect(pending, same(value)); pending = null;
  }
}
class FakeRepository implements CompanyAllowanceIdentityRepository {
  CompanyAllowanceIdentityData value = data();
  bool lostReply = false;
  bool failRead = false;
  bool reject = false;
  int writes = 0;
  List<CompanyAllowanceSlot>? requested;
  @override
  Future<CompanyAllowanceIdentityData> read(String companyId) async {
    if (failRead) {
      throw StateError('offline');
    }
    return value;
  }
  @override
  Future<CompanyAllowanceIdentityData> adopt(String companyId, List<CompanyAllowanceSlot> observed) async {
    writes++;requested = observed;
    if (reject) {
      throw PostgrestException(message: 'allowance source version conflict', code: '40001');
    }
    value = data(adopted: true, version: 1, events: [allowanceHistoryEntry(observed, 1, adoption: true)]);
    if (lostReply) {
      throw StateError('lost reply after commit');
    }
    return value;
  }
  @override
  Future<CompanyAllowanceIdentityData> save(String companyId, int version, CompanyAllowanceSlot slot) async {
    writes++;final target = [for (final old in value.slots) old.slot == slot.slot ? slot : old];requested = target;
    value = data(adopted: true, version: version + 1, values: target, events: [...value.history, allowanceHistoryEntry(target, version + 1)]);
    if (lostReply) {
      throw StateError('lost reply after commit');
    }
    return value;
  }
  @override
  Future<CompanyAllowanceHistoryPage> history(String companyId, {int? beforeVersion, int limit = 50}) async => const CompanyAllowanceHistoryPage([], null);
}
Future<void> showPage(WidgetTester tester, FakeRepository repository, MemoryStore store) async {
  await tester.pumpWidget(MaterialApp(home: CompanyAllowanceIdentityPage(companyId: company, repository: repository, pendingStore: store)));
  await tester.pumpAndSettle();
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('history cursors reject nonprogress and unordered pages', () {
    final first = allowanceHistoryEntry(slots(), 2);
    final second = allowanceHistoryEntry(slots(), 1);
    expect(() => validateAllowanceHistoryWindow([first, second], 2), throwsFormatException);
    expect(() => validateAllowanceHistoryWindow([first, first], 2), throwsFormatException);
    expect(() => validateAllowanceHistoryWindow([second, first], 1), throwsFormatException);
    expect(() => validateAllowanceHistoryWindow([], 1), throwsFormatException);
    expect(() => validateAllowanceHistoryWindow([first, second], 0), throwsFormatException);
    validateAllowanceHistoryWindow([first, second], 1);
  });
  test('strict state rejects missing version, wrong company and collapsed IDs', () {
    final raw = {'contract_version': 1, 'company_id': company, 'version': 0, 'adopted': false,
      'observed_slots': slots().map((s) => s.toJson()).toList(), 'items': [], 'history': []};
    expect(CompanyAllowanceIdentityData.parse(raw, company).slots[1].amountYen, 50);
    for (final bad in [{...raw, 'version': null}, {...raw, 'company_id': 'other'}, {...raw, 'observed_slots': []}]) {
      expect(() => CompanyAllowanceIdentityData.parse(bad, company), throwsFormatException);
    }
  });
  test('old DB missing named RPC only; authorization and unrelated RPC failures propagate', () async {
    for (final error in [
      PostgrestException(message: 'read_company_allowance_identity_admin missing', code: 'PGRST202'),
      PostgrestException(message: 'other function missing', code: 'PGRST202'),
      PostgrestException(message: 'denied', code: '42501'),
    ]) {
      final repo = SupabaseCompanyAllowanceIdentityRepository(invoke: (_, __) async => throw error);
      await expectLater(repo.read(company), throwsA(error.message.startsWith('read_company')
        ? isA<CompanyAllowanceIdentityUnavailable>() : isA<PostgrestException>()));
    }
  });
  test('restart journal stays actor/company scoped and requires exact event/actor/values/IDs', () async {
    final folder = await Directory.systemTemp.createTemp('allowance-journal-test-');
    addTearDown(() => folder.delete(recursive: true));
    var who = actor;
    final store = FileCompanyAllowanceIdentityPendingStore(currentActor: () => who, directory: () async => folder);
    final pending = CompanyAllowanceIdentityPending(companyId: company, actorId: actor, expectedVersion: 0,
      adoption: true, slots: slots(), stableIds: const {});
    await store.write(pending);
    final restarted = FileCompanyAllowanceIdentityPendingStore(currentActor: () => actor, directory: () async => folder);
    final loaded = (await restarted.read(company))!;
    expect(loaded.matches(allowanceHistoryEntry(slots(), 1, adoption: true)), true);
    expect(loaded.matches(allowanceHistoryEntry(slots(), 2, adoption: true)), false);
    expect(loaded.matches(allowanceHistoryEntry(slots(), 1, adoption: true, who: 'other')), false);
    expect(await restarted.read('other company'), isNull);
    final edited = CompanyAllowanceIdentityPending(companyId: company, actorId: actor, expectedVersion: 1,
      adoption: false, slots: slots(), stableIds: const {'1': 'wrong UUID'});
    expect(edited.matches(allowanceHistoryEntry(slots(), 2)), false);
    who = 'other';await expectLater(store.read(company), throwsStateError);
    await restarted.clear(loaded);expect(await restarted.read(company), isNull);
  });
  test('file journal rejects unknown overwrite and corruption and restores flushed temporary record', () async {
    final folder = await Directory.systemTemp.createTemp('allowance-file-journal-');
    addTearDown(() => folder.delete(recursive: true));
    final store = FileCompanyAllowanceIdentityPendingStore(currentActor: () => actor, directory: () async => folder);
    final pending = CompanyAllowanceIdentityPending(companyId: company, actorId: actor, expectedVersion: 0, adoption: true, slots: slots(), stableIds: const {});
    await store.write(pending);await expectLater(store.write(pending), throwsStateError);
    final files = await Directory('${folder.path}/company-allowance-identity-pending-v1').list().toList();
    final file = files.whereType<File>().singleWhere((file) => file.path.endsWith('.json'));
    await file.rename('${file.path}.tmp');
    final restarted = FileCompanyAllowanceIdentityPendingStore(currentActor: () => actor, directory: () async => folder);
    expect((await restarted.read(company))!.toJson(), pending.toJson());
    await file.writeAsString('{broken', flush: true);
    await expectLater(restarted.read(company), throwsFormatException);
    await expectLater(restarted.write(pending), throwsStateError);
  });
  test('two independent stores serialize the same key and do not overwrite the first journal', () async {
    final folder = await Directory.systemTemp.createTemp('allowance-journal-race-');
    addTearDown(() => folder.delete(recursive: true));
    final stores = List.generate(2, (_) => FileCompanyAllowanceIdentityPendingStore(currentActor: () => actor, directory: () async => folder));
    final pending = CompanyAllowanceIdentityPending(companyId: company, actorId: actor, expectedVersion: 0, adoption: true, slots: slots(), stableIds: const {});
    final results = await Future.wait(stores.map((store) => store.write(pending).then((_) => true, onError: (_) => false)));
    expect(results.where((success) => success).length, 1);
    expect((await stores[0].read(company))!.toJson(), pending.toJson());
  });
  testWidgets('initial 3 slots require explicit confirmation; cancel writes nothing', (tester) async {
    final repo = FakeRepository();final store = MemoryStore();await showPage(tester, repo, store);
    await tester.tap(find.text('登録済み手当を確認'));await tester.pumpAndSettle();
    expect(find.textContaining('2：未登録／日／¥50'), findsWidgets);
    await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();expect(repo.writes, 0);expect(store.pending, isNull);
  });
  testWidgets('lost committed adoption blocks resubmit and recovers from exact saved source', (tester) async {
    final repo = FakeRepository()..lostReply = true;final store = MemoryStore();await showPage(tester, repo, store);
    await tester.tap(find.text('登録済み手当を確認'));await tester.pumpAndSettle();
    await tester.tap(find.text('確認して保存'));await tester.pumpAndSettle();expect(repo.writes, 1);
    expect(store.pending, isNotNull);expect(find.text('編集'), findsNothing);
    repo.failRead = true;await tester.tap(find.text('保存状態を再確認'));await tester.pumpAndSettle();
    expect(store.pending, isNotNull);expect(repo.writes, 1);
    repo.failRead = false;await tester.tap(find.text('保存状態を再確認'));await tester.pumpAndSettle();
    expect(store.pending, isNull);expect(find.text('編集'), findsOneWidget);expect(repo.writes, 1);
  });
  testWidgets('same values with wrong actor never resolve unknown result', (tester) async {
    final repo = FakeRepository()..lostReply = true;final store = MemoryStore();await showPage(tester, repo, store);
    await tester.tap(find.text('登録済み手当を確認'));await tester.pumpAndSettle();await tester.tap(find.text('確認して保存'));await tester.pumpAndSettle();
    repo.value = data(adopted: true, version: 1, events: [allowanceHistoryEntry(slots(), 1, adoption: true, who: 'other')]);
    await tester.tap(find.text('保存状態を再確認'));await tester.pumpAndSettle();
    expect(store.pending, isNotNull);expect(find.text('編集'), findsNothing);expect(find.textContaining('先の保存結果'), findsOneWidget);
  });
  testWidgets('definite SQL rejection clears only that journal and requires a fresh read before editing', (tester) async {
    final repo = FakeRepository()..reject = true;final store = MemoryStore();await showPage(tester, repo, store);
    await tester.tap(find.text('登録済み手当を確認'));await tester.pumpAndSettle();await tester.tap(find.text('確認して保存'));await tester.pumpAndSettle();
    expect(repo.writes, 1);expect(store.pending, isNull);expect(find.text('登録済み手当を確認'), findsNothing);
    await tester.tap(find.text('保存状態を再確認'));await tester.pumpAndSettle();
    expect(find.text('登録済み手当を確認'), findsOneWidget);expect(repo.writes, 1);
  });
  testWidgets('retirement is explicit and preserves the existing price/unit', (tester) async {
    final repo = FakeRepository()..value = data(adopted: true, version: 1, events: [allowanceHistoryEntry(slots(), 1, adoption: true)]);
    final store = MemoryStore();await showPage(tester, repo, store);
    await tester.tap(find.text('廃止'));await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();expect(repo.writes, 0);
    await tester.tap(find.text('廃止'));await tester.pumpAndSettle();await tester.tap(find.text('確認して保存'));await tester.pumpAndSettle();
    expect(repo.requested![0].active, false);expect(repo.requested![0].amountYen, 700);expect(repo.requested![0].unit, '回');
    expect(repo.requested![1].amountYen, 50);expect(store.pending, isNull);expect(repo.writes, 1);
  });
  testWidgets('scope ABA during an edit dialog permanently disables stale input', (tester) async {
    final repo = FakeRepository()..value = data(adopted: true, version: 1, events: [allowanceHistoryEntry(slots(), 1, adoption: true)]);
    final store = MemoryStore();
    await showPage(tester, repo, store);
    await tester.tap(find.text('編集')); await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(home: CompanyAllowanceIdentityPage(companyId: 'other-company', repository: repo, pendingStore: store)));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: CompanyAllowanceIdentityPage(companyId: company, repository: repo, pendingStore: store)));
    await tester.pump();
    await tester.tap(find.text('内容を確認')); await tester.pumpAndSettle();
    expect(repo.writes, 0); expect(store.pending, isNull);
    expect(find.text('確認して保存'), findsNothing);
    expect(find.textContaining('開き直してください'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '保存状態を再確認')).onPressed, isNull);
  });

}

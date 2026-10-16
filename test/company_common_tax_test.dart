import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_common_tax_page.dart';
import 'package:sk_works/features/settings/company_common_tax_pending.dart';
import 'package:sk_works/features/settings/company_common_tax_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const company = '10000000-0000-0000-0000-000000000001';
const otherCompany = '10000000-0000-0000-0000-000000000002';
const actor = '20000000-0000-0000-0000-000000000001';
const otherActor = '20000000-0000-0000-0000-000000000002';
const rid = '40000000-0000-4000-8000-000000009001';
Map<String, dynamic> _copy(Object? value) => Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
Map<String, dynamic> _fixtures() => _copy(jsonDecode(File('test/fixtures/company_common_tax_sql_response.json').readAsStringSync()));
CompanyCommonTaxRequest _request({String cid = company, String uid = actor, String id = rid}) {
  final state = _fixtures()['initial'] as Map;
  return CompanyCommonTaxRequest(companyId: cid, actorId: uid, requestId: id, expectedVersion: 0,
    expectedSource: commonTaxObject(state['expected_source']), taxRate: CompanyCommonTaxRate.parse('8.5'), welfareRate: CompanyCommonTaxRate.parse('12.3456'));
}
Map<String, dynamic> _commit(CompanyCommonTaxRequest request) {
  final value = _copy(_fixtures()['initial']);
  value['version'] = request.expectedVersion + 1; value['company_id'] = request.companyId;
  value['tax_rate'] = request.taxRate.number; value['welfare_rate'] = request.welfareRate.number;
  value['expected_source'] = {...request.expectedSource, 'tax_rate': request.taxRate.number, 'welfare_rate': request.welfareRate.number};
  value.addAll({'request_id': request.requestId, 'committed_version': request.expectedVersion + 1, 'id_map': []});
  return value;
}
Map<String, dynamic> _receipt(CompanyCommonTaxRequest request) => {'contract_version': 1, 'company_id': request.companyId,
  'request_id': request.requestId, 'found': true, 'actor_id': request.actorId, 'operation': 'tax', 'payroll_type': null,
  'expected_version': request.expectedVersion, 'request_payload': request.payload,
  'committed_version': request.expectedVersion + 1, 'result': _commit(request)};
class _Repository implements CompanyCommonTaxRepository {
  String? actor = '20000000-0000-0000-0000-000000000001';
  final changes = StreamController<String?>.broadcast(sync: true);
  Map<String, dynamic> value = _copy(_fixtures()['initial']);
  int reads = 0;
  int receipts = 0;
  final saves = <CompanyCommonTaxRequest>[];
  Object? readError;
  Object? saveError;
  bool receiptFound = false;
  bool wrongReceipt = false;
  Completer<void>? readGate;
  Completer<void>? saveGate;
  void Function(CompanyCommonTaxRequest)? beforeSave;
  @override
  String? get actorId => actor;
  @override
  Stream<String?> get actorChanges => changes.stream;
  @override
  Future<CompanyCommonTaxState> read(String companyId) async {
    reads++;
    await readGate?.future;
    if (readError != null) throw readError!;
    return CompanyCommonTaxState.parse(value, companyId);
  }
  @override
  Future<CompanyCommonTaxState> save(CompanyCommonTaxRequest request) async {
    saves.add(request); beforeSave?.call(request);
    await saveGate?.future;
    if (saveError != null) throw saveError!;
    final result = _commit(request);
    value = {...result}..remove('request_id')..remove('committed_version')..remove('id_map');
    receiptFound = true;
    return request.validateCommit(result);
  }
  @override
  Future<CompanyCommonTaxState?> receipt(CompanyCommonTaxRequest request) async {
    receipts++;
    if (!receiptFound) return request.validateReceipt({'contract_version': 1, 'company_id': request.companyId, 'request_id': request.requestId, 'found': false});
    return request.validateReceipt({..._receipt(request), if (wrongReceipt) 'operation': 'allowances'});
  }
  void switchActor(String? id) { actor = id; changes.add(id); }
}
class _Store implements CompanyCommonTaxPendingStore {
  _Store(this.repository);
  final _Repository repository;
  CompanyCommonTaxRequest? value;
  bool failWrite = false;
  bool failClear = false;
  int writes = 0;
  int clears = 0;
  int reads = 0;
  @override
  String actorId() => repository.actorId ?? (throw StateError('No actor'));
  @override
  Future<CompanyCommonTaxRequest?> read(String companyId) async { reads++; return value; }
  @override
  Future<void> write(CompanyCommonTaxRequest request) async {
    writes++;
    if (failWrite) throw const FileSystemException('synthetic flush failure');
    if (value != null) throw StateError('Pending exists');
    value = request;
  }
  @override
  Future<void> clear(CompanyCommonTaxRequest request) async {
    if (failClear || value == null || !commonTaxEqual(request.toJson(), value!.toJson())) throw StateError('Exact cleanup failed');
    clears++; value = null;
  }
}
Future<void> _frames(WidgetTester tester) async {
  await tester.pump(); await tester.pump(const Duration(milliseconds: 400)); await tester.pump();
}
Future<void> _show(WidgetTester tester, _Repository repository, _Store store, {bool embedded = false}) async {
  tester.view.physicalSize = const Size(1200, 1800); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  final page = CompanyCommonTaxPage(companyId: company, repository: repository, pendingStore: store, embedded: embedded);
  await tester.pumpWidget(MaterialApp(home: embedded ? Scaffold(body: page) : page));
  await _frames(tester);
}
Finder _tax() => find.byKey(const Key('company-common-tax'));
Finder _welfare() => find.byKey(const Key('company-common-welfare'));
String _text(WidgetTester tester, Finder finder) => tester.widget<TextFormField>(finder).controller!.text;
Future<void> _edit(WidgetTester tester, {String tax = '8.5', String welfare = '12.3456'}) async {
  await tester.enterText(_tax(), tax); await tester.enterText(_welfare(), welfare); await _frames(tester);
}
Future<void> _save(WidgetTester tester) async { await tester.tap(find.widgetWithText(FilledButton, '保存')); await _frames(tester); }
void main() {
  test('actual isolated SQL percentage state, tax commit, exact receipt and viewer parse', () {
    final f = _fixtures(); final request = _request();
    expect(CompanyCommonTaxState.parse(f['initial'], company).taxRate.text, '10');
    expect(request.validateCommit(f['saved']).welfareRate.text, '12.3456');
    expect(request.validateReceipt(f['receipt'])!.taxRate.text, '8.5');
    expect(CompanyCommonTaxState.parse(f['viewer'], company).canEdit, false);
    final absent = {...commonTaxObject(f['missing']), 'request_id': rid};
    expect(request.validateReceipt(absent), null);
    expect(request.expectedSource['legacy_slots'], commonTaxObject(f['initial'])['expected_source']['legacy_slots']);
  });
  test('rates keep percentages exact, reject ranges, precision and malformed states', () {
    for (final value in ['0', '10', '100', '12.3456', '0.0001']) {
      final rate = CompanyCommonTaxRate.parse(value);
      expect(CompanyCommonTaxRate.fromNumber(rate.number).scaled, rate.scaled);
    }
    for (final value in ['', '-1', '100.0001', '1e2', '1.00001', 'NaN', '1.2.3']) {
      expect(() => CompanyCommonTaxRate.parse(value), throwsFormatException);
    }
    final initial = _copy(_fixtures()['initial']);
    expect(() => CompanyCommonTaxState.parse({...initial, 'company_id': otherCompany}, company), throwsFormatException);
    expect(() => CompanyCommonTaxState.parse({...initial, 'tax_rate': '10'}, company), throwsFormatException);
    expect(() => CompanyCommonTaxState.parse({...initial, 'can_edit': 1}, company), throwsFormatException);
    expect(() => CompanyCommonTaxState.parse({...initial, 'raw_private_field': 'not allowed'}, company), throwsFormatException);
  });
  test('receipt rejects other operation, actor, company, payload, target and malformed result', () {
    final request = _request();
    for (final changes in [
      {'operation': 'allowances'}, {'actor_id': otherActor}, {'company_id': otherCompany}, {'request_id': '40000000-0000-4000-8000-000000000999'},
      {'payroll_type': 'daily'}, {'expected_version': 1}, {'committed_version': 3}, {'request_payload': {...request.payload, 'tax_rate': 9}},
      {'result': {..._commit(request), 'welfare_rate': 1}}, {'result': {..._commit(request), 'id_map': [{'id': rid}]}},
    ]) {
      expect(() => request.validateReceipt({..._receipt(request), ...changes}), throwsFormatException);
    }
    final altered = _commit(request); (altered['expected_source'] as Map)['legacy_version'] = 5;
    expect(() => request.validateCommit(altered), throwsFormatException);
  });
  test('legacy CAS snapshot is immutable and preserves NULL, padded name and free unit', () {
    final initial = _copy(_fixtures()['initial']);
    final source = initial['expected_source'] as Map;
    final slots = source['legacy_slots'] as List;
    (slots[0] as Map)['name'] = '${' ' * 100}旧名${' ' * 100}'; (slots[0] as Map)['unit'] = ' 組 ';
    final state = CompanyCommonTaxState.parse(initial, company);
    final oldName = (state.expectedSource['legacy_slots'] as List)[0]['name'];
    (slots[0] as Map)['name'] = 'external mutation';
    expect((state.expectedSource['legacy_slots'] as List)[0]['name'], oldName);
    expect(() => (state.expectedSource['legacy_slots'] as List)[0]['name'] = 'mutation', throwsUnsupportedError);
    expect((state.expectedSource['legacy_slots'] as List)[2]['name'], null);
  });
  test('native journal survives reopen, exact cleanup and actor/company namespace separation', () async {
    final directory = await Directory.systemTemp.createTemp('sko-tax-journal-'); addTearDown(() => directory.delete(recursive: true));
    final sentinel = File('${directory.path}/old-payroll-pending')..writeAsStringSync('unchanged');
    final one = FileCompanyCommonTaxPendingStore(currentActor: () => actor, directory: () async => directory);
    await one.write(_request());
    final reopened = FileCompanyCommonTaxPendingStore(currentActor: () => actor, directory: () async => directory);
    expect(commonTaxEqual((await reopened.read(company))!.toJson(), _request().toJson()), true);
    await expectLater(reopened.write(_request()), throwsStateError);
    await expectLater(reopened.clear(_request(id: '40000000-0000-4000-8000-000000009002')), throwsStateError);
    final another = FileCompanyCommonTaxPendingStore(currentActor: () => otherActor, directory: () async => directory);
    expect(await another.read(company), null); await another.write(_request(uid: otherActor));
    await reopened.write(_request(cid: otherCompany));
    await reopened.clear(_request());
    expect(await reopened.read(company), null);
    expect(await reopened.read(otherCompany), isNotNull); expect(await another.read(company), isNotNull);
    expect(sentinel.readAsStringSync(), 'unchanged');
  });
  test('native atomic temp recovery, corrupt record protection and actor change refusal', () async {
    final directory = await Directory.systemTemp.createTemp('sko-tax-recovery-'); addTearDown(() => directory.delete(recursive: true));
    String? current = actor;
    final store = FileCompanyCommonTaxPendingStore(currentActor: () => current, directory: () async => directory);
    await store.write(_request());
    final file = Directory('${directory.path}/sko-company-common-tax-pending-v1').listSync().whereType<File>().singleWhere((f) => f.path.endsWith('.json'));
    final temporary = await file.rename('${file.path}.tmp');
    final next = FileCompanyCommonTaxPendingStore(currentActor: () => current, directory: () async => directory);
    expect((await next.read(company))!.requestId, rid); expect(await temporary.exists(), false);
    current = otherActor; await expectLater(next.read(company), throwsStateError);
    current = actor;
    final main = File(file.path); await main.rename('${main.path}.tmp');
    await File('${main.path}.tmp').writeAsString('{bad', flush: true);
    final corrupt = FileCompanyCommonTaxPendingStore(currentActor: () => actor, directory: () async => directory);
    await expectLater(corrupt.read(company), throwsFormatException);
    expect(await File('${main.path}.tmp').exists(), true);
  });
  testWidgets('embedded two-item editor flushes journal before exact save and reports completion', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository();
    final active = _Store(repo); addTearDown(repo.changes.close);
    repo.beforeSave = (request) { expectSync(commonTaxEqual(active.value!.toJson(), request.toJson()), true); };
    await _show(tester, repo, active, embedded: true);
    expect(find.byType(Scaffold), findsOneWidget); expect(find.byType(TextFormField), findsNWidgets(2));
    expect(_text(tester, _tax()), '10'); expect(_text(tester, _welfare()), '0');
    await _edit(tester); await _save(tester);
    expect(repo.saves.length, 1); expect(active.writes, 1); expect(active.value, null);
    expect(find.text('消費税・福利厚生費を保存しました。'), findsOneWidget);
    expect(_text(tester, _tax()), '8.5');
  });
  testWidgets('viewer and pre-save role downgrade cannot write and preserve the draft', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository(); final active = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, active); await _edit(tester, tax: '11');
    repo.value['can_edit'] = false;
    await _save(tester);
    expect(repo.saves, isEmpty); expect(active.writes, 0); expect(_text(tester, _tax()), '11');
    expect(tester.widget<TextFormField>(_tax()).readOnly, true);
    await tester.pumpWidget(const SizedBox());
    await _show(tester, repo, active);
    expect(find.text('閲覧のみ'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, null);
  });
  testWidgets('flush failure sends no mutation and preserves input', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository(); final store = _Store(repo)..failWrite = true; addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester, tax: '11'); await _save(tester);
    expect(repo.saves, isEmpty); expect(_text(tester, _tax()), '11');
    expect(find.textContaining('保存は完了していません'), findsOneWidget);
  });
  testWidgets('unknown survives page reopen, never resends, and only exact receipt clears it', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository()..saveError = TimeoutException('synthetic'); final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester); await _save(tester);
    expect(repo.saves.length, 1); expect(store.value, isNotNull); expect(_text(tester, _tax()), '8.5');
    await tester.pumpWidget(const SizedBox()); await _show(tester, repo, store);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, null);
    await tester.tap(find.text('保存状態を再確認')); await _frames(tester);
    expect(repo.saves.length, 1); expect(store.value, isNotNull);
    repo.receiptFound = true; repo.wrongReceipt = true;
    await tester.tap(find.text('保存状態を再確認')); await _frames(tester);
    expect(store.value, isNotNull); expect(repo.saves.length, 1);
    repo.wrongReceipt = false; repo.saveError = null;
    repo.value = {..._commit(store.value!)}..remove('request_id')..remove('committed_version')..remove('id_map');
    await tester.tap(find.text('保存状態を再確認')); await _frames(tester);
    expect(store.value, null); expect(repo.saves.length, 1);
    expect(find.text('消費税・福利厚生費の保存を確認しました。'), findsOneWidget);
    await _edit(tester, tax: '9');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, isNotNull);
  });
  testWidgets('CAS rejection preserves draft, requires explicit latest review, and never auto retries', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository()..saveError = const PostgrestException(message: 'synthetic', code: '40001');
    final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester, tax: '11'); await _save(tester);
    expect(repo.saves.length, 1); expect(store.value, null); expect(_text(tester, _tax()), '11');
    repo.value['version'] = 1; repo.value['tax_rate'] = 13; (repo.value['expected_source'] as Map)['tax_rate'] = 13;
    await tester.tap(find.text('最新設定を再確認')); await _frames(tester);
    expect(_text(tester, _tax()), '11'); expect(repo.saves.length, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, null);
    await tester.tap(find.text('最新設定を確認')); await _frames(tester);
    expect(find.textContaining('保存済み：消費税 13%'), findsOneWidget);
    await tester.tap(find.text('確認して編集を続ける')); await _frames(tester);
    expect(repo.saves.length, 1); expect(_text(tester, _tax()), '11');
    repo.saveError = null; await _save(tester);
    expect(repo.saves.length, 2); expect(repo.saves.last.expectedVersion, 1);
  });
  testWidgets('duplicate callback is ignored while a save is pending', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final gate = Completer<void>(); final repo = _Repository()..saveGate = gate; final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester);
    final callback = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed!;
    callback(); callback(); await _frames(tester);
    expect(repo.saves.length, 1); expect(store.writes, 1);
    gate.complete(); await _frames(tester); expect(store.value, null);
  });
  testWidgets('initial background makes no reads and resume keeps an unsaved permitted draft', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final repo = _Repository(); final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store);
    expect(repo.reads, 0); expect(store.reads, 0); expect(find.byType(TextFormField), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await _frames(tester);
    await _edit(tester, tax: '11');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await _frames(tester);
    expect(find.byType(TextFormField), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await _frames(tester);
    expect(_text(tester, _tax()), '11'); expect(repo.saves, isEmpty);
  });
  testWidgets('late save after background is resolved by receipt only, not replayed', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final gate = Completer<void>(); final repo = _Repository()..saveGate = gate; final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester); await _save(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await _frames(tester);
    expect(store.value, isNotNull); expect(repo.saves.length, 1);
    gate.complete(); await _frames(tester);
    expect(store.value, isNotNull);
    await tester.tap(find.text('保存状態を再確認')); await _frames(tester);
    expect(repo.saves.length, 1); expect(store.value, null);
    expect(find.text('消費税・福利厚生費の保存を確認しました。'), findsOneWidget);
  });
  testWidgets('actor switch discards inputs, late responses and the other actor journal', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository(); final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester);
    repo.switchActor(otherActor); await _frames(tester);
    expect(_text(tester, _tax()), ''); expect(_text(tester, _welfare()), '');
    expect(find.textContaining('ログイン状態が変わりました'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, null);
    expect(repo.saves, isEmpty);
  });
  testWidgets('missing new API is preparation state and never calls a legacy saver', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository()..readError = const CompanyCommonTaxUnavailable(); final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store);
    expect(find.textContaining('準備中'), findsOneWidget); expect(repo.saves, isEmpty);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, null);
  });
  testWidgets('company replacement invalidates the old draft without fetching or writing as the new company', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final repo = _Repository(); final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store); await _edit(tester);
    final reads = repo.reads;
    await tester.pumpWidget(MaterialApp(home: CompanyCommonTaxPage(companyId: otherCompany, repository: repo, pendingStore: store)));
    await _frames(tester);
    expect(_text(tester, _tax()), ''); expect(_text(tester, _welfare()), '');
    expect(repo.reads, reads); expect(repo.saves, isEmpty);
    expect(find.textContaining('会社・ログイン状態が変わりました'), findsOneWidget);
  });
  testWidgets('late initial response after an actor switch cannot repopulate cleared inputs', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final gate = Completer<void>(); final repo = _Repository()..readGate = gate; final store = _Store(repo); addTearDown(repo.changes.close);
    await _show(tester, repo, store);
    repo.switchActor(otherActor); await _frames(tester);
    gate.complete(); await _frames(tester);
    expect(_text(tester, _tax()), ''); expect(_text(tester, _welfare()), '');
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, null);
    expect(repo.saves, isEmpty);
  });

}

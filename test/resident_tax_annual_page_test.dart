import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/resident_tax_annual_page.dart';
import 'package:sk_works/features/payroll/resident_tax_annual_repository.dart';

const a = '40000000-0000-0000-0000-000000000001';
const b = '40000000-0000-0000-0000-000000000002';

class AnnualFixture implements ResidentTaxAnnualRepository {
  bool canEdit = true, scopeComplete = true, loseReply = false, reject = false;
  int saves = 0, undos = 0;
  String? lastRequest;
  Map<String, dynamic>? receipt;
  List<ResidentTaxAnnualInput> sent = [];
  final rows = <Map<String, dynamic>>[
    {'worker_id': a, 'name': '社員A', 'current_amount_yen': 5000,
      'amounts': List.filled(12, 5000), 'previous_amounts': List.filled(12, 4000),
      'current_amounts': List.filled(12, 5000), 'confirmed': false, 'excluded': false,
      'reason': null, 'source': {'version': 1}, 'confirmed_at': null, 'last_updated_at': null,
      'undo_request_id': null, 'undo_before_amounts': null},
    {'worker_id': b, 'name': '社員B', 'current_amount_yen': 2000,
      'amounts': List.filled(12, 2000), 'previous_amounts': List.filled(12, null),
      'current_amounts': List.filled(12, 2000), 'confirmed': false, 'excluded': false,
      'reason': null, 'source': {'version': 1}, 'confirmed_at': null, 'last_updated_at': null,
      'undo_request_id': null, 'undo_before_amounts': null},
  ];
  Map<String, dynamic> get snapshot => {'cohort_hash': 'fixture', 'workers': [
    for (final row in rows) {'worker_id': row['worker_id'], 'source': row['source']},
  ]};
  @override
  Future<ResidentTaxAnnualData> read(String companyId, int fiscalYear, {String? requestId}) async => ResidentTaxAnnualData.fromJson({
    'company_id': companyId, 'fiscal_year': fiscalYear, 'previous_fiscal_year': fiscalYear - 1,
    'current_fiscal_year': fiscalYear, 'can_edit': canEdit, 'scope_complete': scopeComplete,
    'complete': rows.every((r) => r['confirmed'] == true), 'snapshot': snapshot,
    'workers': rows, 'receipt': requestId == lastRequest ? receipt : null,
  }, companyId, fiscalYear);
  @override
  Future<void> save(ResidentTaxAnnualData current, List<ResidentTaxAnnualInput> entries, String requestId) async {
    if (reject) throw const ResidentTaxAnnualReloadRequired();
    saves++; sent = entries; lastRequest = requestId;
    for (final entry in entries) {
      final row = rows.singleWhere((r) => r['worker_id'] == entry.workerId);
      row['undo_before_amounts'] = List<int>.from(row['amounts'] as List);
      row['undo_request_id'] = requestId; row['amounts'] = entry.amounts;
      row['current_amounts'] = entry.amounts; row['confirmed'] = true;
      row['source'] = {'version': 2}; row['confirmed_at'] = '2030-05-01T02:03:00Z';
      row['last_updated_at'] = '2030-05-01T02:03:00Z';
    }
    receipt = {'company_id': current.companyId, 'fiscal_year': current.fiscalYear,
      'request_id': requestId, 'snapshot': snapshot};
    if (loseReply) throw StateError('lost reply');
  }
  @override
  Future<void> undo(ResidentTaxAnnualData current, ResidentTaxAnnualWorker worker, String requestId) async {
    if (reject) throw const ResidentTaxAnnualReloadRequired();
    undos++; lastRequest = requestId;
    final row = rows.singleWhere((r) => r['worker_id'] == worker.id);
    row['amounts'] = worker.undoAmounts!; row['current_amounts'] = worker.undoAmounts!;
    row['confirmed'] = false; row['confirmed_at'] = null; row['last_updated_at'] = '2030-05-02T02:03:00Z';
    row['source'] = {'version': 3}; row['undo_request_id'] = null; row['undo_before_amounts'] = null;
    receipt = {'company_id': current.companyId, 'fiscal_year': current.fiscalYear,
      'request_id': requestId, 'snapshot': snapshot, 'undone': true};
  }
}

Future<void> openAnnual(WidgetTester t, AnnualFixture repository, {double scale = 1}) async {
  await t.pumpWidget(MaterialApp(home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: ResidentTaxAnnualUpdatePage(companyId: 'company', fiscalYear: 2030, repository: repository))));
  await t.pumpAndSettle();
}
Finder field(String id) => find.byKey(ValueKey('annual-input-$id'));
Finder update(String id) => find.byKey(ValueKey('annual-update-$id'));
Finder undo(String id) => find.byKey(ValueKey('annual-undo-$id'));
Future<void> confirmUpdate(WidgetTester t, String id) async {
  await t.ensureVisible(update(id)); await t.tap(update(id)); await t.pumpAndSettle();
  await t.tap(find.text('確認して更新')); await t.pumpAndSettle();
}

void main() {
  test('unknown and monthly amounts are never flattened into a guessed value', () {
    expect(residentTaxAnnualDisplay(List.filled(12, null)), '未確認');
    expect(residentTaxAnnualDisplay([null, ...List.filled(11, 100)]), '一部未確認');
    expect(residentTaxAnnualDisplay([200, ...List.filled(11, 100)]), '月別');
    expect(residentTaxAnnualDisplay(List.filled(12, 0)), '0円');
  });
  testWidgets('readonly prior/current years and server timestamp; one-row same-value update', (t) async {
    final f = AnnualFixture(); await openAnnual(t, f);
    expect(find.byType(TextField), findsNWidgets(2)); expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.text('2029年度'), findsNWidgets(2)); expect(find.text('2030年度'), findsNWidgets(2));
    expect(find.text('最終更新日：未更新'), findsNWidgets(2));
    await confirmUpdate(t, a);
    expect(f.saves, 1); expect(f.sent.single.workerId, a); expect(f.sent.single.amounts, List.filled(12, 5000));
    expect(f.rows[1]['confirmed'], false); expect(find.textContaining('2030/05/01 11:03'), findsOneWidget);
  });
  testWidgets('cancel writes nothing; explicit zero saves only selected employee', (t) async {
    final f = AnnualFixture(); await openAnnual(t, f); await t.enterText(field(a), '0');
    await t.ensureVisible(update(a)); await t.tap(update(a)); await t.pumpAndSettle();
    expect(find.textContaining('5000 → 0円'), findsOneWidget);
    await t.tap(find.text('戻る')); await t.pumpAndSettle(); expect(f.saves, 0);
    await confirmUpdate(t, a); expect(f.sent.single.amounts, List.filled(12, 0)); expect(f.rows[1]['amounts'], List.filled(12, 2000));
  });
  testWidgets('mixed months remain intact for confirmation and cannot be overwritten with one input', (t) async {
    final f = AnnualFixture(); final months = [5100, 5000, 5500, ...List.filled(9, 5000)];
    f.rows[0]['amounts'] = months; f.rows[0]['current_amounts'] = months; await openAnnual(t, f);
    expect(find.text('月別'), findsOneWidget); await t.enterText(field(a), '6000');
    await t.ensureVisible(update(a)); await t.tap(update(a)); await t.pumpAndSettle();
    expect(find.textContaining('個別給料設定で各月額'), findsOneWidget); expect(f.saves, 0);
    await t.enterText(field(a), ''); await confirmUpdate(t, a); expect(f.sent.single.amounts, months);
  });
  testWidgets('unregistered current tax requires explicit notice amount', (t) async {
    final f = AnnualFixture(); f.rows[0]['current_amounts'] = List.filled(12, null); await openAnnual(t, f);
    await t.ensureVisible(update(a)); await t.tap(update(a)); await t.pumpAndSettle();
    expect(find.textContaining('未確認を0円とは扱いません'), findsOneWidget); expect(f.saves, 0);
  });
  testWidgets('another employee unsaved input survives one-row update', (t) async {
    final f = AnnualFixture(); await openAnnual(t, f); await t.enterText(field(b), '2222'); await confirmUpdate(t, a);
    expect(t.widget<TextField>(field(b)).controller!.text, '2222'); expect(f.rows[1]['amounts'], List.filled(12, 2000));
  });
  testWidgets('lost reply stops repeat updates until matching receipt is read', (t) async {
    final f = AnnualFixture()..loseReply = true; await openAnnual(t, f); await confirmUpdate(t, a);
    expect(find.textContaining('保存結果を確認できません'), findsOneWidget); expect(update(a), findsNothing); expect(f.saves, 1);
    await t.tap(find.text('住民税の一覧を再読み込み')); await t.pumpAndSettle();
    expect(find.text('住民税を更新しました。'), findsOneWidget); expect(f.saves, 1);
  });
  testWidgets('local undo never writes; saved undo confirms before server mutation and refreshes timestamp', (t) async {
    final f = AnnualFixture(); await openAnnual(t, f); await t.enterText(field(a), '6000');
    await t.ensureVisible(undo(a)); await t.tap(undo(a)); await t.pumpAndSettle();
    expect(t.widget<TextField>(field(a)).controller!.text, '5000'); expect(f.saves, 0); expect(f.undos, 0);
    await t.enterText(field(a), '6000'); await confirmUpdate(t, a);
    await t.ensureVisible(undo(a)); await t.tap(undo(a)); await t.pumpAndSettle();
    expect(find.textContaining('6000 → 5000円'), findsOneWidget); expect(f.undos, 0);
    await t.tap(find.text('確認して元に戻す')); await t.pumpAndSettle();
    expect(f.undos, 1); expect(f.rows[0]['amounts'], List.filled(12, 5000)); expect(f.rows[0]['confirmed'], false);
    expect(find.textContaining('2030/05/02 11:03'), findsOneWidget);
  });
  testWidgets('viewer and incomplete scopes never edit or update', (t) async {
    for (final incomplete in [false, true]) {
      final f = AnnualFixture(); f.canEdit = incomplete; f.scopeComplete = !incomplete;
      await openAnnual(t, f); expect(t.widget<TextField>(field(a)).enabled, false);
      expect(t.widget<TextButton>(update(a)).onPressed, isNull); await t.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('five-column rows remain usable on narrow enlarged display', (t) async {
    t.view.physicalSize = const Size(320, 1000); t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
    await openAnnual(t, AnnualFixture(), scale: 1.3);
    expect(find.text('社員A'), findsOneWidget); expect(field(a), findsOneWidget); expect(update(a), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

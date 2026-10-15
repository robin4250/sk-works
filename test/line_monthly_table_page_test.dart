import 'support/line_test_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/chat/line_import_page.dart';
import 'package:sk_works/features/chat/line_reading_rules.dart';
import 'package:sk_works/features/chat/line_import_repository.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import_page.dart';
import 'package:sk_works/features/chat/line_historical_invoice_page.dart';

class _Auth extends Fake implements GoTrueClient {
  @override
  User? get currentUser => null;
}
class _Client extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _Auth();
}
class _Repository extends LineImportRepository {
  _Repository({this.editable = true, this.assumed = false}) : super(_Client());
  final bool editable, assumed;
  final months = <DateTime>[];
  final saves = <Map<String, dynamic>>[];
  bool failSave = false;
  Map<String, dynamic> _workspace(DateTime month) => {
    'revision': 1, 'can_edit': editable,
    'features': {'attendance': false, 'invoice': true},
    'source_kind': 'mixed', 'source_messages': <Map<String, dynamic>>[],
    'candidate_rows': [<String, dynamic>{
      'work_date': '${month.year}-${month.month.toString().padLeft(2, '0')}-01',
      'worker_id': 'w', 'worker_name': '山田', 'site_id': 's', 'site_name': '現場A',
      'man_days': 1, 'overtime_hours': 0, 'early_hours': 0,
      'work_category': 'day', 'allowance_names': <String>[],
      'confirmed': !assumed, 'excluded': false,
      if (assumed) ...{
        'overtime_hours': 1, 'early_hours': 1,
        'assumed_fields': {'overtime_hours': {'value': 1, 'reason': '残業の時間未記載'},
          'early_hours': {'value': 1, 'reason': '早出の時間未記載'}},
      },
    }],
    'note_comparison': '', 'confirmed': false,
  };
  @override
  Future<Map<String, dynamic>> load(String groupId, String target, DateTime month) async {
    months.add(month);
    return _workspace(month);
  }
  @override
  Future<({List<Map<String, dynamic>> workers, List<Map<String, dynamic>> sites})>
      references(String groupId) async => (
        workers: [{'id': 'w', 'name': '山田'}],
        sites: [{'id': 's', 'name': '現場A', 'customer_id': 'c'}],
      );
  @override
  Future<List<LineReadingRule>> readingRules(String groupId) async => [];
  @override
  Future<List<Map<String, dynamic>>> sources(String groupId) async => [];
  @override
  Future<Map<String, dynamic>> save(Map<String, dynamic> command) async {
    saves.add(command);
    if (failSave) throw StateError('response unavailable');
    return {..._workspace(DateTime.parse(command['p_month'] as String)),
      'revision': 2, 'candidate_rows': command['p_rows'],
      'note_comparison': command['p_note']};
  }
}

Future<void> _mount(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(LineTestApp(home: LineImportPage.monthly(
    initialMonth: DateTime(2026, 9), repositoryOverride: repository,
    groupsLoader: () async => [{'id': 'g', 'name': 'LINE現場'}],
  )));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder, {double delta = 250}) async {
  await tester.scrollUntilVisible(finder, delta, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one assumed quantity can be repaired without clearing another or confirming row', (tester) async {
    final repository = _Repository(assumed: true);
    await _mount(tester, repository);
    await _reveal(tester, find.byType(DataTable));
    final table = tester.widget<DataTable>(find.byType(DataTable));
    final overtimeCell = table.rows.single.cells[5];
    expect((overtimeCell.child as Text).data, '1（仮）');
    overtimeCell.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('残業時間（仮）を確認'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '1'), '3');
    await tester.tap(find.text('この数値を採用'));
    await tester.pumpAndSettle();
    final repaired = tester.widget<DataTable>(find.byType(DataTable));
    expect((repaired.rows.single.cells[5].child as Text).data, '3.0');
    expect((repaired.rows.single.cells[6].child as Text).data, '1（仮）');
    expect(find.text('確認済みの候補はありません。'), findsOneWidget);
  });
  testWidgets('swipe switches months and reimport opens the same group', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository);
    expect(find.text('LINE月別の表'), findsOneWidget);
    await tester.fling(find.byKey(const ValueKey('line-month-swipe')), const Offset(-200, 0), 600);
    await tester.pumpAndSettle();
    expect(repository.months.last, DateTime(2026, 10));
    await tester.fling(find.byKey(const ValueKey('line-month-swipe')), const Offset(200, 0), 600);
    await tester.pumpAndSettle();
    expect(repository.months.last, DateTime(2026, 9));
    await tester.tap(find.text('TXT・ZIPと受信データを月間表へ入れ直す'));
    await tester.pumpAndSettle();
    expect(tester.widget<LineHistoricalMonthlyImportPage>(find.byType(LineHistoricalMonthlyImportPage)).groupId, 'g');
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsaved input and ambiguous saves block month changes and preserve retry', (tester) async {
    final repository = _Repository()..failSave = true;
    await _mount(tester, repository);
    final note = find.widgetWithText(TextField, 'LINEノートの集計・照合メモ');
    await _reveal(tester, note);
    await tester.enterText(note, '手入力で照合');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final month = find.byKey(const ValueKey('line-month-swipe'));
    await _reveal(tester, month, delta: -250);
    await tester.fling(month, const Offset(200, 0), 600);
    await tester.pumpAndSettle();
    expect(repository.months.length, 1);
    await tester.tap(find.text('月間表を保存'));
    await tester.pumpAndSettle();
    expect(repository.saves.single['p_note'], '手入力で照合');
    await tester.fling(month, const Offset(200, 0), 600);
    await tester.pumpAndSettle();
    expect(repository.months.length, 1);
    repository.failSave = false;
    await tester.tap(find.text('同じ内容を再送').first);
    await tester.pumpAndSettle();
    expect(repository.saves[0], repository.saves[1]);
    await tester.fling(month, const Offset(200, 0), 600);
    await tester.pumpAndSettle();
    expect(repository.months.last, DateTime(2026, 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('table rows allow manual correction and save into the monthly draft', (tester) async {
    final repository = _Repository();
    await _mount(tester, repository);
    final date = find.text('2026-09-01');
    await _reveal(tester, date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    final overtime = find.widgetWithText(TextField, '残業時間');
    await tester.ensureVisible(overtime);
    await tester.enterText(overtime, '2.5');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認済みにする'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('月間表を保存'), delta: -250);
    await tester.tap(find.text('月間表を保存'));
    await tester.pumpAndSettle();
    final rows = repository.saves.single['p_rows'] as List;
    expect(rows.single['overtime_hours'], 2.5);
    expect(rows.single['worker_id'], 'w');
    expect(repository.saves.single['p_month'], '2026-09-01');
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly table keeps the selected group and month in historical rates and invoices', (tester) async {
    await _mount(tester, _Repository());
    expect(find.text('金額を確認して請求書を作成'), findsNothing);
    for (final rates in [true, false]) {
      final button = find.text(rates ? 'この月の単価設定' : 'この月の請求書');
      await _reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final page = tester.widget<LineHistoricalInvoicePage>(find.byType(LineHistoricalInvoicePage));
      expect(page.editingRates, rates);
      expect(page.initialGroupId, 'g');
      expect(page.initialMonth, DateTime(2026, 9));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('readonly monthly table cannot edit rows or save', (tester) async {
    await _mount(tester, _Repository(editable: false));
    expect(find.text('月間表を保存'), findsNothing);
    final date = find.text('2026-09-01');
    await _reveal(tester, date);
    await tester.tap(date);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}


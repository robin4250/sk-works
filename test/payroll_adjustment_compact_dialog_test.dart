import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_adjustment_page.dart';
import 'package:sk_works/features/payroll/payroll_adjustment_repository.dart';

class _Repository implements PayrollAdjustmentRepository {
  _Repository({this.canManage = true});
  final bool canManage;
  final created = <Map<String, Object?>>[];
  final savedTypes = <Map<String, Object?>>[];
  final types = <PayrollAdjustmentTypeOption>[
    const PayrollAdjustmentTypeOption(id: 'type-1', label: '道具代', direction: 'deduction', isActive: true),
  ];
  @override
  Future<PayrollAdjustmentAccess> loadAccess() async => PayrollAdjustmentAccess(
    pageLabel: '給与調整', canView: true, canManage: canManage, canRename: false);
  @override
  Future<List<PayrollAdjustmentWorker>> loadWorkers() async => const [
    PayrollAdjustmentWorker(id: 'worker-1', name: '確認社員'),
  ];
  @override
  Future<List<PayrollAdjustmentTypeOption>> loadTypes() async => List.of(types);
  @override
  Future<List<PayrollAdjustmentListItem>> loadAdjustments({String? workerId, DateTime? start, DateTime? end}) async => [];
  @override
  Future<DateTime?> loadLatestStatementPeriodEnd(String workerId) async => DateTime(2026, 10, 31);
  @override
  Future<String> createAdjustment({required String workerId, required String typeId,
      required int amountYen, required DateTime effectiveDate, String? note}) async {
    created.add({'workerId': workerId, 'typeId': typeId, 'amountYen': amountYen,
      'effectiveDate': effectiveDate, 'note': note});
    return 'saved-adjustment';
  }
  @override
  Future<String> saveType({String? id, required String label, required String direction, bool isActive = true}) async {
    savedTypes.add({'label': label, 'direction': direction, 'isActive': isActive});
    types.add(PayrollAdjustmentTypeOption(id: 'type-2', label: label.trim(), direction: direction, isActive: isActive));
    return 'type-2';
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label);
Finder _save() => find.descendant(of: find.byType(AlertDialog).last,
  matching: find.widgetWithText(FilledButton, '登録'));

Future<void> _open(WidgetTester tester, _Repository repository, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final base = ThemeData();
  await tester.pumpWidget(MaterialApp(
    theme: base.copyWith(textTheme: base.textTheme.copyWith(
      bodyLarge: TextStyle(fontSize: size.width > 320 ? 24 : 16),
      bodyMedium: TextStyle(fontSize: size.width > 320 ? 24 : 16),
    )),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)), child: child!),
    home: PayrollAdjustmentPage(repository: repository),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('registration uses phone width and readable compact fields without suppressing text scaling', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    expect(find.text('給与調整を登録'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    expect(tester.getSize(dialog).width, greaterThanOrEqualTo(350));
    expect(tester.getSize(_field('金額')).height, lessThanOrEqualTo(76));
    expect(MediaQuery.textScalerOf(tester.element(_field('金額'))).scale(10), closeTo(13, 0.01));
    expect(find.text('2026/10/31'), findsOneWidget);
    expect(repository.created, isEmpty);
    await tester.tap(find.text('キャンセル').last);
    await tester.pumpAndSettle();
    expect(repository.created, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small phone with keyboard can finish input without saving then register unchanged values explicitly', (tester) async {
    final repository = _Repository();
    await _open(tester, repository, size: const Size(320, 568));
    await tester.enterText(_field('金額'), '1,250');
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_field('備考（任意）'));
    await tester.enterText(_field('備考（任意）'), '  確認用備考  ');
    await tester.pumpAndSettle();
    final done = find.text('入力完了').last;
    expect(tester.getBottomRight(done).dy, lessThanOrEqualTo(568 - 220));
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(find.descendant(of: _field('備考（任意）'), matching: find.byType(EditableText))).focusNode.hasFocus, isFalse);
    expect(repository.created, isEmpty, reason: 'Finishing keyboard input must not register payroll');
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await tester.tap(_save());
    await tester.pumpAndSettle();
    expect(repository.created, [
      {'workerId': 'worker-1', 'typeId': 'type-1', 'amountYen': 1250,
       'effectiveDate': DateTime(2026, 10, 31), 'note': '  確認用備考  '},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank and zero amounts remain invalid and do not reach registration', (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await tester.tap(_save());
    await tester.pump();
    expect(find.text('項目と金額を確認してください'), findsOneWidget);
    expect(repository.created, isEmpty);
    await tester.enterText(_field('金額'), '0');
    await tester.tap(find.text('入力完了').last);
    await tester.pumpAndSettle();
    await tester.tap(_save());
    await tester.pump();
    expect(repository.created, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('item creation remains keyboard safe and keeps deduction default until explicit add', (tester) async {
    final repository = _Repository();
    await _open(tester, repository, size: const Size(320, 568));
    await tester.tap(find.byTooltip('項目追加'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    await tester.enterText(_field('項目名'), '交通費');
    await tester.tap(find.text('入力完了').last);
    await tester.pumpAndSettle();
    expect(repository.savedTypes, isEmpty);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog).last,
      matching: find.widgetWithText(FilledButton, '追加')));
    await tester.pumpAndSettle();
    expect(repository.savedTypes, [{'label': '交通費', 'direction': 'deduction', 'isActive': true}]);
    expect(repository.created, isEmpty);
    expect(find.text('給与調整を登録'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view-only permission still exposes no registration operation', (tester) async {
    final repository = _Repository(canManage: false);
    await tester.pumpWidget(MaterialApp(home: PayrollAdjustmentPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(repository.created, isEmpty);
  });
}

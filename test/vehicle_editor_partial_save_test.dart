import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_editor_page.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';

class _Repository implements VehicleRouteRepository {
  final ids = <String?>[];
  final notified = <String>[];
  bool failNotice = true;
  bool failBody = false;
  @override
  Future<String> saveVehicle({
    String? id,
    required String name,
    required String registrationNumber,
    required double odometerKm,
    required String storageAddress,
  }) async {
    ids.add(id);
    if (failBody) throw StateError('offline');
    return id ?? 'saved-exact-vehicle';
  }
  @override
  Future<List<String>> notifyMissingVehicleDocuments(String id) async {
    notified.add(id);
    if (failNotice) throw StateError('notice offline');
    return ['車検証'];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: VehicleEditorPage(
    repository: repository,
  )));
  await tester.enterText(find.byType(TextField).at(0), '作業車');
  await tester.enterText(find.byType(TextField).at(1), '品川123');
  await tester.enterText(find.byType(TextField).at(2), '1234');
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('確定して保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AlertDialog),
    matching: find.text('確定して保存')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('notification failure retains returned exact ID for retry',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _save(tester);
    expect(repository.ids, [null]);
    expect(find.textContaining('車両本体は保存済みです。'), findsWidgets);
    expect(find.text('保存完了'), findsNothing);
    expect(find.text('作業車'), findsOneWidget);
    repository.failNotice = false;
    await _save(tester);
    expect(repository.ids, [null, 'saved-exact-vehicle']);
    expect(repository.notified,
      ['saved-exact-vehicle', 'saved-exact-vehicle']);
    expect(find.text('保存完了'), findsOneWidget);
    expect(find.textContaining('未登録書類は後から追加してください'), findsOneWidget);
  });

  testWidgets('body failure retains input without claiming saved',
      (tester) async {
    final repository = _Repository()..failBody = true;
    await _open(tester, repository);
    await _save(tester);
    expect(find.text('保存完了'), findsNothing);
    expect(find.textContaining('車両本体は保存済みです。'), findsNothing);
    expect(find.textContaining('保存結果を確認できませんでした'), findsWidgets);
    expect(repository.notified, isEmpty);
    expect(find.text('作業車'), findsOneWidget);
    expect(find.text('品川123'), findsOneWidget);
  });

  testWidgets('subsequent update failure never loses previously returned ID',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _save(tester);
    repository.failBody = true;
    await _save(tester);
    repository.failBody = false;
    repository.failNotice = false;
    await _save(tester);
    expect(repository.ids,
      [null, 'saved-exact-vehicle', 'saved-exact-vehicle']);
    expect(find.text('保存完了'), findsOneWidget);
  });
}

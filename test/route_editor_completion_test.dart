import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/route_editor_page.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';

class _Repository implements VehicleRouteRepository {
  final pending = Completer<String>();
  int saves = 0;
  @override
  Future<String> saveRoute({
    String? id,
    required String name,
    required String notes,
    String? responsibleName,
    String? responsiblePhone,
    required List<Map<String, Object?>> stops,
  }) {
    saves++;
    return pending.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute<bool>(
          builder: (_) => RouteEditorPage(
            sites: const [], customers: const [], partners: const [],
            vehicles: const [], repository: repository,
          ),
        )),
        child: const Text('一覧'),
      ),
    )),
  ));
  await tester.tap(find.text('一覧'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '朝のルート');
  await tester.enterText(find.byType(TextField).at(3), '東京都墨田区');
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('確定して保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(
    of: find.byType(AlertDialog), matching: find.text('確定して保存'),
  ));
  await tester.pump();
}

void main() {
  testWidgets('completion follows successful save; busy prevents back and duplicate save',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _confirm(tester);
    expect(repository.saves, 1);
    expect(find.text('保存完了'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(RouteEditorPage), findsOneWidget);
    expect(repository.saves, 1);
    repository.pending.complete('route-id');
    await tester.pumpAndSettle();
    expect(find.text('保存完了'), findsOneWidget);
    await tester.tap(find.text('ルート一覧へ'));
    await tester.pumpAndSettle();
    expect(find.byType(RouteEditorPage), findsNothing);
  });

  testWidgets('failure retains route input and offers retry without completion',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await _confirm(tester);
    repository.pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('保存完了'), findsNothing);
    expect(find.byType(RouteEditorPage), findsOneWidget);
    expect(find.text('朝のルート'), findsOneWidget);
    expect(find.text('東京都墨田区'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('cancel confirmation does not save and releases busy state',
      (tester) async {
    final repository = _Repository();
    await _open(tester, repository);
    await tester.tap(find.text('確定して保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(find.text('朝のルート'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}

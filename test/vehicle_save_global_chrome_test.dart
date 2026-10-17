import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_editor_page.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';
import 'package:sk_works/widgets/sko_scroll_chrome.dart';

class _DelayedVehicleRepository implements VehicleRouteRepository {
  final response = Completer<String>();
  final savedIds = <String?>[];
  final notifiedIds = <String>[];

  @override
  Future<String> saveVehicle({
    String? id,
    required String name,
    required String registrationNumber,
    required double odometerKm,
    required String storageAddress,
  }) {
    savedIds.add(id);
    return response.future;
  }

  @override
  Future<List<String>> notifyMissingVehicleDocuments(String id) async {
    notifiedIds.add(id);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('global scroll and edge back preserve pending vehicle save and return once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(650, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SkoScrollChromeController.visible.value = true;
    addTearDown(() => SkoScrollChromeController.visible.value = true);
    final repository = _DelayedVehicleRepository();
    var returned = 0;
    var listUpdates = 0;

    await tester.pumpWidget(MaterialApp(
      navigatorKey: SkoScrollChromeController.navigatorKey,
      builder: (_, child) => SkoGlobalScrollChrome(child: child!),
      home: StatefulBuilder(builder: (context, updateList) {
        return Scaffold(
          appBar: AppBar(title: const Text('車両一覧 fixture')),
          body: Column(children: [
            Text('一覧更新 $listUpdates', key: const Key('list-refresh-count')),
            TextButton(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => VehicleEditorPage(
                    repository: repository,
                  )),
                );
                returned++;
                if (saved == true && context.mounted) {
                  updateList(() => listUpdates++);
                }
              },
              child: const Text('車両登録を開く'),
            ),
          ]),
        );
      }),
    ));
    await tester.tap(find.text('車両登録を開く'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '作業車');
    await tester.enterText(find.byType(TextField).at(1), '品川123');
    await tester.enterText(find.byType(TextField).at(2), '1234');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // Real ScrollNotifications drive the same global controller used by the app.
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(SkoScrollChromeController.visible.value, isFalse);
    await tester.scrollUntilVisible(
      find.text('確定して保存'), 100, scrollable: find.descendant(of: find.byType(ListView),
        matching: find.byType(Scrollable)).first);
    await tester.tap(find.text('確定して保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog),
      matching: find.text('確定して保存')));
    await tester.pump();
    expect(repository.savedIds, [null]);
    expect(find.text('保存完了'), findsNothing);

    Future<void> edgeBack() async {
      final gesture = await tester.startGesture(const Offset(8, 300));
      await gesture.moveBy(const Offset(100, 0));
      await gesture.up();
      await tester.pump();
    }
    // Exercise the actual global left-edge listener -> navigator.maybePop path.
    await edgeBack();
    expect(find.byType(VehicleEditorPage), findsOneWidget);
    expect(returned, 0);
    expect(listUpdates, 0);
    expect(repository.savedIds, [null]);

    repository.response.complete('saved-exact-vehicle');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.notifiedIds, ['saved-exact-vehicle']);
    expect(find.text('保存完了'), findsOneWidget);
    expect(returned, 0);
    // The real completion dialog also refuses the global edge-back gesture.
    await edgeBack();
    expect(find.text('保存完了'), findsOneWidget);
    await tester.tap(find.text('車両一覧へ'));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleEditorPage), findsNothing);
    expect(find.text('車両一覧 fixture'), findsOneWidget);
    expect(find.text('一覧更新 1'), findsOneWidget);
    expect(returned, 1);
    expect(listUpdates, 1);
    expect(repository.savedIds, [null]);
    expect(repository.notifiedIds, ['saved-exact-vehicle']);
    expect(SkoScrollChromeController.navigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/operations/vehicle_route_repository.dart';
import 'package:sk_works/features/operations/vehicle_route_selection_page.dart';

class Access implements VehicleRouteSelectionAccess {
  @override
  String? selectionActorId = 'actor';
  bool fail = false;
  String? selected;
  int loads = 0, saves = 0, unrelatedLoads = 0;
  List<Map<String, dynamic>>? routeRows;
  Completer<List<Map<String, dynamic>>>? delayed;
  @override
  Future<List<Map<String, dynamic>>> routes({bool activeOnly = false}) async {
    loads++;
    if (fail) throw StateError('offline');
    return delayed?.future ??
        Future.value(
          routeRows ??
              [
                {'id': 'route', 'route_name': 'A現場 → B現場'},
              ],
        );
  }

  @override
  Future<List<Map<String, dynamic>>> vehicles({bool activeOnly = false}) async {
    unrelatedLoads++;
    throw StateError('vehicle list is unavailable');
  }

  @override
  Future<Map<String, dynamic>> loadTodaySelection() async => {
    'route_assignment_id': selected,
  };
  @override
  Future<void> saveTodayRouteSelection(String? routeId) async {
    saves++;
    selected = routeId;
  }

  @override
  Future<void> saveTodayVehicleSelection(String? vehicleId) async =>
      throw StateError('wrong mode');
}

Future<void> open(WidgetTester tester, Access access) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VehicleRouteSelectionPage(
        mode: VehicleRouteSelectionMode.route,
        access: access,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'selected route shows ordered destinations and clears without writes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = Access()
        ..selected = 'route'
        ..routeRows = [
          {
            'id': 'route',
            'route_name': '巡回',
            'route_stops': [
              {'stop_order': 3, 'address': '最後の訪問住所'},
              {
                'stop_order': 1,
                'source_label': '取引会社の長い名称を含む訪問先',
                'address': '東京都の長い住所を表示しても横にはみ出さない',
              },
              {
                'stop_order': 2,
                'sites': {'name': 'B現場', 'address': '現場の登録住所'},
              },
            ],
          },
        ];
      await open(tester, access);
      expect(find.text('回る順番（3地点）'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('取引会社の長い名称を含む訪問先')).dy,
        lessThan(tester.getTopLeft(find.text('B現場')).dy),
      );
      expect(
        tester.getTopLeft(find.text('B現場')).dy,
        lessThan(tester.getTopLeft(find.text('最後の訪問住所')).dy),
      );
      expect(find.text('現場の登録住所'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Rendering must not reorder or change the repository's source rows.
      expect(
        (access.routeRows!.first['route_stops'] as List).first['stop_order'],
        3,
      );
      expect(access.saves, 0);
      expect(access.loads, 1);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ルートを使わない').last);
      await tester.pumpAndSettle();
      expect(find.text('回る順番（3地点）'), findsNothing);
      expect(access.selected, 'route');
      expect(access.saves, 0);
    },
  );
  testWidgets(
    'empty selected route is identified without fabricating destinations',
    (tester) async {
      await open(tester, Access()..selected = 'route');
      expect(find.text('回る順番（0地点）'), findsOneWidget);
      expect(find.text('地点が未登録です。ルート管理で登録してください。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'route load failure can retry without fetching unrelated vehicles or writing',
    (tester) async {
      final access = Access()..fail = true;
      await open(tester, access);
      expect(find.text('再読み込み'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      access.fail = false;
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('確定して保存'), findsOneWidget);
      expect(access.loads, 2);
      expect(access.unrelatedLoads, 0);
      expect(access.saves, 0);
    },
  );
  testWidgets(
    'inactive saved route stays selected without crashing or silently clearing storage',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = Access()..selected = 'inactive';
      await open(tester, access);
      expect(tester.takeException(), isNull);
      expect(find.text('選択済みのルートは現在利用できません'), findsWidgets);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(access.selected, 'inactive');
      expect(access.saves, 0);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A現場 → B現場').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(access.selected, 'inactive');
      await tester.tap(find.text('確定して保存'));
      await tester.pumpAndSettle();
      expect(access.selected, 'route');
      expect(access.saves, 1);
    },
  );
  testWidgets(
    'duplicate retry and leaving during load cannot save or update disposed page',
    (tester) async {
      final access = Access()..fail = true;
      await open(tester, access);
      access.fail = false;
      access.delayed = Completer<List<Map<String, dynamic>>>();
      final retry = tester
          .widget<OutlinedButton>(find.byType(OutlinedButton))
          .onPressed!;
      retry();
      retry();
      await tester.pump();
      expect(access.loads, 2);
      await tester.pumpWidget(const MaterialApp(home: Text('closed')));
      access.delayed!.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(access.saves, 0);
    },
  );
  testWidgets('changed actor cannot save the previous actor selection', (
    tester,
  ) async {
    final access = Access();
    await open(tester, access);
    access.selectionActorId = 'other';
    await tester.tap(find.text('確定して保存'));
    await tester.pumpAndSettle();
    expect(access.saves, 0);
    expect(find.text('再読み込み'), findsOneWidget);
  });
  testWidgets('actor change while loading hides stale selection', (
    tester,
  ) async {
    final access = Access()..fail = true;
    await open(tester, access);
    access.fail = false;
    access.delayed = Completer<List<Map<String, dynamic>>>();
    await tester.tap(find.text('再読み込み'));
    await tester.pump();
    access.selectionActorId = 'other';
    access.delayed!.complete([
      {'id': 'route', 'route_name': 'previous actor route'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('previous actor route'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('再読み込み'), findsOneWidget);
    expect(access.saves, 0);
  });
}

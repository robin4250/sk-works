import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_verification_page.dart';

void main() {
  testWidgets(
    'selected route prevents changing clock-in to an individual site',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceDestinationSiteField(
              siteId: null,
              routeId: 'selected-route',
              sites: const [
                {'id': 'site', 'name': '江戸川'},
              ],
              locked: false,
              onChanged: (value) => chosen = value,
            ),
          ),
        ),
      );
      final dropdown = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>),
      );
      expect(dropdown.value, isNull);
      expect(find.text('未登録（ルートで出勤）'), findsOneWidget);
      expect(dropdown.onChanged, isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('江戸川'), findsNothing);
      expect(chosen, isNull);
    },
  );
  testWidgets('ordinary site selection remains available without a route', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceDestinationSiteField(
            siteId: null,
            routeId: null,
            sites: const [
              {'id': 'site', 'name': '江戸川'},
            ],
            locked: false,
            onChanged: (value) => chosen = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('江戸川').last);
    await tester.pumpAndSettle();
    expect(chosen, 'site');
  });
}

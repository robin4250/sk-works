import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/work_destination_selection_page.dart';

void main() {
  testWidgets(
    'route selection clears displayed fixed site and disables its menu',
    (tester) async {
      String? chosen;
      Widget form(String? route) => MaterialApp(
        home: Scaffold(
          body: WorkDestinationSiteField(
            siteId: 'site',
            routeId: route,
            sites: const [
              {'id': 'site', 'name': '江戸川'},
            ],
            saving: false,
            onChanged: (value) => chosen = value,
          ),
        ),
      );
      await tester.pumpWidget(form(null));
      expect(
        tester
            .widget<DropdownButton<String?>>(
              find.byType(DropdownButton<String?>),
            )
            .value,
        'site',
      );
      await tester.pumpWidget(form('route'));
      final dropdown = tester.widget<DropdownButton<String?>>(
        find.byType(DropdownButton<String?>),
      );
      expect(dropdown.value, isNull);
      expect(dropdown.onChanged, isNull);
      expect(find.text('未登録'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('江戸川'), findsNothing);
      expect(chosen, isNull);
      await tester.pumpWidget(form(null));
      expect(
        tester
            .widget<DropdownButton<String?>>(
              find.byType(DropdownButton<String?>),
            )
            .onChanged,
        isNotNull,
      );
    },
  );
}

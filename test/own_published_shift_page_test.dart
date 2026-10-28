import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/own_published_shift_page.dart';

void main() {
  testWidgets('unreleased direct route stays closed without initializing Supabase', (tester) async {
    await tester.pumpWidget(MaterialApp(home: OwnPublishedShiftPage(month: DateTime(2026, 10))));
    await tester.pump();
    expect(find.text('準備中です。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

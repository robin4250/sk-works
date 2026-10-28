import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_day_editor.dart';

void main() {
  testWidgets('holiday can be selected without losing the draft', (tester) async {
    var draft = const ShiftDayDraft(holiday: false, night: false, siteId: 's',
      start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 17, minute: 0),
      checkLate: true, checkEarly: true);
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) =>
      Scaffold(body: SingleChildScrollView(child: ShiftDayEditor(value: draft,
        sites: const [ShiftSiteOption(id: 's', name: '現場')],
        onChanged: (next) => setState(() => draft = next)))))));
    expect(find.text('出勤先'), findsOneWidget);
    await tester.tap(find.text('休日'));
    await tester.pump();
    expect(draft.holiday, isTrue);
    expect(find.text('出勤先'), findsNothing);
    await tester.tap(find.text('休日'));
    await tester.pump();
    expect(draft.siteId, 's');
    expect(find.text('出勤先'), findsOneWidget);
  });
}

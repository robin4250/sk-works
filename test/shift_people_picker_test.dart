import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shifts/shift_people_picker.dart';

void main() {
  testWidgets('individual and all selections only contain visible members', (tester) async {
    Set<String> selected = {'unavailable'};
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      return Scaffold(body: ShiftPeoplePicker(
        people: const [ShiftPersonOption(id: 'a', name: '社員A'), ShiftPersonOption(id: 'b', name: '社員B')],
        selectedIds: selected, onChanged: (value) => setState(() => selected = value),
      ));
    })));
    await tester.tap(find.text('すべて選択'));
    await tester.pump();
    expect(selected, {'a', 'b'});
    await tester.tap(find.text('社員A'));
    await tester.pump();
    expect(selected, {'b'});
    await tester.tap(find.text('すべて選択'));
    await tester.pump();
    expect(selected, {'a', 'b'});
    await tester.tap(find.text('すべて選択'));
    await tester.pump();
    expect(selected, isEmpty);
  });
}

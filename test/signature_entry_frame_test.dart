import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_entry_frame.dart';

void main() {
  for (final role in ['報告者', '責任者']) {
    testWidgets('$role frame shows name and one-tap guidance on small screen', (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var tapped = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ListTile(
        subtitle: SignatureEntryFrame(role: role, signerName: '試験記入者'),
        onTap: () { tapped++; }))));
      await t.tap(find.text('横向きでサインしてください'));
      expect(tapped, 1);
      expect(find.text('$role：試験記入者'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}

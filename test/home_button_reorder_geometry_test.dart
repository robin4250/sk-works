import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';

void main() {
  for (final columns in [1, 2, 3, 4]) {
    testWidgets('reorder preserves button geometry in $columns columns', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget home(bool reorder) => MaterialApp(
        home: Scaffold(
          body: FriendlyHomeContent(
            identity: const HomeIdentity(role: 'owner', companyName: '会社', displayName: '本人'),
            requiredDocumentAttention: const RequiredDocumentAttention(missingCount: 0, missingNames: [], needsLicense: false, needsQualification: false),
            moduleEnabled: (_) => true,
            gridColumns: columns,
            showAttendanceReport: false,
            showTodayAttendance: false,
            visibleHomeKeys: const {'general', 'admin', 'viewer', 'manager'},
            shortcuts: const [
              HomeShortcut('general', '日報', Icons.edit),
              HomeShortcut('admin', '社員登録', Icons.people, access: HomeShortcutAccess.admin),
              HomeShortcut('viewer', '出勤表', Icons.calendar_month, access: HomeShortcutAccess.viewer),
              HomeShortcut('manager', '書類登録', Icons.folder, access: HomeShortcutAccess.subAdmin),
            ],
            onOpen: (_) async {},
            onRefresh: () async {},
            onReorderAction: reorder ? (_, _) async {} : null,
          ),
        ),
      );
      const keys = ['general', 'admin', 'viewer', 'manager'];
      await tester.pumpWidget(home(false));
      await tester.pump();
      final original = <String, Size>{
        for (final key in keys) key: tester.getSize(find.byKey(ValueKey('home-button-$key'))),
      };
      await tester.pumpWidget(home(true));
      await tester.pump();
      for (final key in keys) {
        final button = find.byKey(ValueKey('home-button-$key'));
        expect(tester.getSize(button), original[key], reason: '$key keeps its original cell size');
        final handle = find.byKey(ValueKey('home-reorder-$key'));
        expect(tester.getRect(button).inflate(3).contains(tester.getCenter(handle)), isTrue,
            reason: '$key handle remains within the button');
      }
      expect(tester.takeException(), isNull);
    });
  }
}

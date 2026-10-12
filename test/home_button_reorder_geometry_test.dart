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
  testWidgets('button body long press reorders without opening its action', (tester) async {
    final moves = <String>[];
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FriendlyHomeContent(
      identity: const HomeIdentity(role: 'owner', companyName: '会社', displayName: '本人'),
      requiredDocumentAttention: const RequiredDocumentAttention(missingCount: 0, missingNames: [], needsLicense: false, needsQualification: false),
      moduleEnabled: (_) => true, gridColumns: 2,
      showAttendanceReport: false, showTodayAttendance: false,
      visibleHomeKeys: const {'first', 'second'},
      shortcuts: const [HomeShortcut('first', '一番', Icons.edit), HomeShortcut('second', '二番', Icons.folder)],
      onOpen: (key) async { opened.add(key); }, onRefresh: () async {},
      onReorderAction: (source, target) async { moves.add('$source->$target'); },
    ))));
    await tester.pump();
    final first = find.byKey(const ValueKey('home-button-first'));
    final second = find.byKey(const ValueKey('home-button-second'));
    await tester.tap(first);
    expect(opened, ['first']);
    opened.clear();
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveTo(tester.getCenter(second));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, ['first->second']);
    expect(opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('employee resources uses one viewer border and keeps its action', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FriendlyHomeContent(
      identity: const HomeIdentity(role: 'worker', companyName: '会社', displayName: '本人'),
      requiredDocumentAttention: const RequiredDocumentAttention(missingCount: 0, missingNames: [], needsLicense: false, needsQualification: false),
      moduleEnabled: (_) => true, showAttendanceReport: false, showTodayAttendance: false,
      visibleHomeKeys: const {'employee_resources'},
      shortcuts: const [HomeShortcut('employee_resources', '社員資格書類', Icons.folder, access: HomeShortcutAccess.viewer)],
      onOpen: (key) async { opened.add(key); }, onRefresh: () async {},
    ))));
    await tester.pump();
    final button = find.byKey(const ValueKey('home-button-employee_resources'));
    bool bordered(Widget widget) => widget is Container && widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).border != null;
    expect(find.descendant(of: button, matching: find.byWidgetPredicate(bordered)), findsOneWidget);
    expect(find.ancestor(of: button, matching: find.byWidgetPredicate(bordered)), findsNothing);
    await tester.tap(button);
    expect(opened, ['employee_resources']);
    expect(tester.takeException(), isNull);
  });

}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/main.dart';
import 'package:sk_works/widgets/sko_scroll_chrome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_worker_list_page.dart';
import 'package:sk_works/features/sites/admin_site_financial_page.dart';
import 'package:sk_works/features/payroll/payment_certificates_page.dart';
import 'package:sk_works/features/shared/related_action_footer.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';

void main() {
  for (final type in ['attendance', 'sites', 'payment']) {
    testWidgets(
      '$type footer opens the supplied existing destination and stays absent without access',
      (tester) async {
        var opens = 0;
        Future<void> open() async {
          opens++;
        }

        Widget page(Future<void> Function()? callback) => switch (type) {
          'attendance' => AttendanceWorkerListPage(onOpenManagement: callback),
          'sites' => AdminSiteFinancialPage(onOpenMap: callback),
          _ => PaymentCertificatesPage(onOpenSettings: callback),
        };
        final label = switch (type) {
          'attendance' => '勤怠管理',
          'sites' => '現場マップ',
          _ => '支払証明書設定',
        };
        await tester.pumpWidget(MaterialApp(home: page(null)));
        await tester.pump();
        expect(find.byType(RelatedActionFooter), findsNothing);
        await tester.pumpWidget(MaterialApp(home: page(open)));
        await tester.pump();
        expect(find.widgetWithText(FilledButton, label), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, label));
        await tester.pump();
        expect(opens, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  Widget home({bool attention = false}) => MaterialApp(
    home: Scaffold(
      body: FriendlyHomeContent(
        identity: const HomeIdentity(
          role: 'member',
          companyName: '会社',
          displayName: '本人',
        ),
        requiredDocumentAttention: RequiredDocumentAttention(
          missingCount: attention ? 1 : 0,
          missingNames: const [],
          needsLicense: false,
          needsQualification: false,
          notificationPreviews: attention
              ? const ['日報確認：内容1\n内容2\n内容3\n内容4']
              : const [],
        ),
        moduleEnabled: (_) => true,
        showAttendanceReport: false,
        visibleHomeKeys: {
          'attendance_today',
          for (var i = 0; i < 30; i++) 'action-$i',
        },
        shortcuts: [
          for (var i = 0; i < 30; i++)
            HomeShortcut('action-$i', '操作$i', Icons.work_outline),
        ],
        onOpen: (_) async {},
        onRefresh: () async {},
        onReorderAction: (_, _) async {},
      ),
    ),
  );
  testWidgets(
    'compact home uses one-line explanation and three-line notification preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(home(attention: true));
      await tester.pump();
      final heading = tester.widget<Text>(find.text('要対応'));
      expect(heading.style!.fontSize, 17.5);
      final preview = tester.widget<Text>(find.text('日報確認：内容1\n内容2\n内容3\n内容4'));
      expect(preview.maxLines, 3);
      expect(preview.style!.fontSize, 11);
      final explanation = tester.widget<Text>(
        find.text('自社と下請けを分けて、現場ごとの出勤人数を確認できます。'),
      );
      expect(explanation.maxLines, 1);
      expect(explanation.softWrap, isFalse);
      expect(
        find.ancestor(
          of: find.text(explanation.data!),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'card text scrolls after a pause and button text scrolls before long press',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(home());
      await tester.pump();
      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      for (final label in ['本日の出勤', '操作2']) {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        final before = position.pixels;
        final gesture = await tester.startGesture(
          tester.getCenter(find.text(label)),
        );
        await tester.pump(Duration(milliseconds: label == '本日の出勤' ? 900 : 100));
        // First cross touch slop, then continue the same finger movement.
        await gesture.moveBy(const Offset(0, -25));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(0, -145));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          position.pixels,
          greaterThan(before),
          reason: 'Scroll starting on $label',
        );
        expect(tester.takeException(), isNull);
      }
      // A deliberate long press continues to provide the existing reorder feedback.
      await tester.ensureVisible(find.byKey(const ValueKey('home-reorder-action-8')));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('home-reorder-action-8'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(10, 20));
      await tester.pump();
      expect(find.text('操作8'), findsNWidgets(2));
      await gesture.up();
      await tester.pump();
    },
  );
  testWidgets('TOP scroll extent stays fixed when chrome visibility changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SkoScrollChromeController.visible.value = true;
    addTearDown(() => SkoScrollChromeController.visible.value = true);
    await tester.binding.setSurfaceSize(const Size(375, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SkWorksApp(allowLocalFallback: true));
    await tester.pump();
    final contentFinder = find.byType(FriendlyHomeContent);
    final initial = tester
        .widget<FriendlyHomeContent>(contentFinder)
        .contentTopInset;
    final scrollable = find
        .descendant(of: contentFinder, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(100);
    await tester.pump();
    final extent = position.maxScrollExtent;
    SkoScrollChromeController.visible.value = false;
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<FriendlyHomeContent>(contentFinder).contentTopInset,
      initial,
    );
    expect(position.maxScrollExtent, extent);
    expect(position.pixels, 100);
    SkoScrollChromeController.visible.value = true;
    await tester.pump(const Duration(milliseconds: 200));
    expect(position.maxScrollExtent, extent);
    expect(position.pixels, 100);
    expect(tester.takeException(), isNull);
  });
}

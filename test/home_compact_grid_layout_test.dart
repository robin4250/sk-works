import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required int columns,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    const identity = HomeIdentity(
      role: 'owner',
      companyName: '墨田建設株式会社',
      displayName: '管理者テストユーザー',
      permissions: {
        'can_manage_people': true,
        'can_view_invoices': true,
        'can_view_admin_site_data': true,
        'can_manage_attendance': true,
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendlyHomeContent(
            identity: identity,
            requiredDocumentAttention: const RequiredDocumentAttention(
              missingCount: 2,
              missingNames: ['書類A', '書類B'],
              needsLicense: false,
              needsQualification: false,
            ),
            moduleEnabled: (_) => true,
            gridColumns: columns,
            actionOrder: const ['attendance_verify', 'attendance_today'],
            visibleHomeKeys: const {
              'attendance_verify',
              'attendance_today',
            },
            onOpen: (_) async {},
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('three-column home grid fits compact iPhone portrait', (tester) async {
    await pumpHome(
      tester,
      columns: 3,
      size: const Size(320, 568),
    );

    expect(find.text('要対応'), findsOneWidget);
    expect(find.text('本日の勤怠報告'), findsOneWidget);
    expect(find.text('本日の出勤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four-column home grid fits iPhone portrait', (tester) async {
    await pumpHome(
      tester,
      columns: 4,
      size: const Size(375, 812),
    );

    expect(find.text('要対応'), findsOneWidget);
    expect(find.text('本日の勤怠報告'), findsOneWidget);
    expect(find.text('本日の出勤'), findsOneWidget);
    final source = File('lib/features/home/friendly_home_content.dart').readAsStringSync();
    expect(source, contains('primary: false'));
    expect(source, contains('padding: EdgeInsets.zero'));
    expect(source, contains('fourColumns\n              ? Column('));
    expect(source, contains('final needsTwoLines = painter.width > constraints.maxWidth'));
    expect(source, contains('maxLines: needsTwoLines ? 2 : 1'));
    expect(source, contains('fontSize: fourColumns ? 9.5'));
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/app_update_check_service.dart';
import 'package:sk_works/features/settings/app_update_notice_dialog.dart';
import 'package:sk_works/features/settings/app_version_policy.dart';

void main() {
  AppUpdateNoticeData notice(AppUpdateRequirement requirement) {
    return AppUpdateNoticeData(
      currentVersion: '1.0.0',
      latestVersion: '2.0.0',
      requirement: requirement,
      storeUrl: Uri.parse('https://apps.apple.com/jp/app/sko/id123'),
    );
  }

  testWidgets('optional update allows later', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateNoticeDialog(
            notice: notice(AppUpdateRequirement.optional),
            onOpenStore: () {},
          ),
        ),
      ),
    );

    expect(find.text('新しいバージョンがあります'), findsOneWidget);
    expect(find.text('あとで'), findsOneWidget);
    expect(find.text('App Storeで更新'), findsOneWidget);
  });

  testWidgets('required update removes later action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppUpdateNoticeDialog(
            notice: notice(AppUpdateRequirement.required),
            onOpenStore: () {},
          ),
        ),
      ),
    );

    expect(find.text('アプリの更新が必要です'), findsOneWidget);
    expect(find.text('あとで'), findsNothing);
    expect(find.text('App Storeで更新'), findsOneWidget);
  });
}

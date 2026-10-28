import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/apple_recovery_notice.dart';

void main() {
  testWidgets('held keeps current login and never reports success', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      AppleRecoveryNotice(state: AppleRecoveryNoticeState.held))));
    expect(find.text('Apple連携を確認しています'), findsOneWidget);
    expect(find.textContaining('現在のログイン方法を引き続き使えます'), findsOneWidget);
    expect(find.text('Apple連携を確認しました'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('unavailable and confirmed results remain distinct', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      AppleRecoveryNotice(state: AppleRecoveryNoticeState.unavailable))));
    expect(find.text('連携の状態を確認できません'), findsOneWidget);
    expect(find.text('Apple連携を確認しました'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      AppleRecoveryNotice(state: AppleRecoveryNoticeState.linked))));
    expect(find.text('Apple連携を確認しました'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      AppleRecoveryNotice(state: AppleRecoveryNoticeState.retry))));
    expect(find.text('Appleの本人確認からやり直せます'), findsOneWidget);
    expect(find.text('Apple連携を確認しました'), findsNothing);
  });
}

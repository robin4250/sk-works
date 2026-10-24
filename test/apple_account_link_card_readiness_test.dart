import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/apple_account_link.dart';
import 'package:sk_works/features/auth/apple_account_link_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReadinessSource extends AppleAccountLink {
  ReadinessSource(super.client) : super(
    settingsUrl: Uri.parse('https://apple-card.invalid/auth/v1/settings'),
    publicKey: 'synthetic-public');
  AppleLinkReadiness result = AppleLinkReadiness.providerDisabled;
  Future<AppleLinkReadiness>? next;
  int starts = 0;
  @override Future<AppleLinkReadiness> readiness() async {
    final pending = next; next = null;
    return pending == null ? result : await pending;
  }
  @override Future<void> begin() async { starts++; }
}

void main() {
  late SupabaseClient client;
  late ReadinessSource source;
  setUp(() {
    client = SupabaseClient('https://apple-card.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    source = ReadinessSource(client);
  });
  tearDown(() async { await source.dispose(); await client.dispose(); });

  Future<void> show(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(700, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: AppleAccountLinkCard(source: source)))));
    await t.pumpAndSettle();
  }

  testWidgets('provider disabled, unknown, and recent proof missing have separate non-actionable states', (t) async {
    await show(t);
    expect(find.textContaining('Apple連携は提供準備中です。'), findsOneWidget);
    expect(find.text('このアカウントにAppleを追加'), findsNothing);
    source.result = AppleLinkReadiness.unavailable;
    await t.tap(find.text('Apple追加の状態を再確認')); await t.pumpAndSettle();
    expect(find.textContaining('本人の登録状況を確認できませんでした。'), findsOneWidget);
    expect(find.textContaining('Apple連携は提供準備中です。'), findsNothing);
    source.result = AppleLinkReadiness.recentOAuthRequired;
    await t.tap(find.text('Apple追加の状態を再確認')); await t.pumpAndSettle();
    expect(find.text('同じログインを保った追加の本人確認が必要です。この接続は準備中です。'), findsOneWidget);
    expect(find.text('このアカウントにAppleを追加'), findsNothing);
    expect(source.starts, 0);
  });

  testWidgets('checking removes old start action and recovery only exposes verified readiness', (t) async {
    source.result = AppleLinkReadiness.ready;
    await show(t);
    expect(find.text('このアカウントにAppleを追加'), findsOneWidget);
    final pending = Completer<AppleLinkReadiness>(); source.next = pending.future;
    await t.tap(find.text('Apple追加の状態を再確認')); await t.pump();
    expect(find.text('このアカウントにAppleを追加'), findsNothing);
    pending.complete(AppleLinkReadiness.unavailable); await t.pumpAndSettle();
    expect(find.text('このアカウントにAppleを追加'), findsNothing);
    source.result = AppleLinkReadiness.ready;
    await t.tap(find.text('Apple追加の状態を再確認')); await t.pumpAndSettle();
    expect(find.text('このアカウントにAppleを追加'), findsOneWidget);
    expect(find.text('このアカウントへのApple連携は確認済みです。'), findsNothing);
    expect(source.starts, 0);
  });

  testWidgets('already linked has no start action and help preserves current login', (t) async {
    source.result = AppleLinkReadiness.linked;
    await show(t);
    expect(find.text('このアカウントへのApple連携は確認済みです。'), findsOneWidget);
    expect(find.text('このアカウントにAppleを追加'), findsNothing);
    await t.tap(find.text('？ Apple追加について')); await t.pumpAndSettle();
    expect(find.textContaining('ログアウトせず、現在の方法を引き続き使えます。'), findsOneWidget);
    expect(source.starts, 0);
  });

  testWidgets('late readiness after card disposal has no effect', (t) async {
    await show(t);
    final pending = Completer<AppleLinkReadiness>(); source.next = pending.future;
    await t.tap(find.text('Apple追加の状態を再確認')); await t.pump();
    await t.pumpWidget(const SizedBox.shrink());
    pending.complete(AppleLinkReadiness.ready); await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(source.starts, 0);
  });
}

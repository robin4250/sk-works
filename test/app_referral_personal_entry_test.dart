import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/referrals/app_referral_personal_entry.dart';
import 'package:sk_works/features/referrals/app_referral_page.dart';
import 'package:sk_works/features/referrals/app_referral_repository.dart';

class PersonalReferralRepository extends AppReferralRepository {
  PersonalReferralRepository() : super(SupabaseClient('https://test.invalid', 'test',
    authOptions: const AuthClientOptions(autoRefreshToken: false)));
  String actor = 'self';
  bool deny = false;
  bool disableOnOpen = false;
  bool changeActor = false;
  int loads = 0;
  final snapshot = <String, dynamic>{
    'enabled': true, 'can_invite': true, 'public_enabled': false,
    'distribution_url_ready': true, 'invitations': <Object>[],
  };
  @override
  String? get currentActorId => actor;
  @override
  Future<Map<String, dynamic>> load({bool master = false}) async {
    expect(master, isFalse);
    loads++;
    if (deny) {
      throw StateError('denied');
    }
    if (loads > 1 && disableOnOpen) {
      snapshot['can_invite'] = false;
    }
    if (loads > 1 && changeActor) {
      actor = 'someone-else';
    }
    return Map<String, dynamic>.from(snapshot);
  }
}

Future<void> show(WidgetTester tester, PersonalReferralRepository repository) async {
  addTearDown(repository.client.dispose);
  await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: AppReferralPersonalEntry(repository: repository),
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner/admin server permission opens only personal page', (tester) async {
    await show(tester, PersonalReferralRepository());
    await tester.tap(find.text('SKOアプリ招待・自分の紹介履歴'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppReferralPage>(find.byType(AppReferralPage)).master, isFalse);
    expect(find.text('紹介設定・全体履歴'), findsNothing);
  });
  testWidgets('public invite permission opens personal page without local admin role', (tester) async {
    final repository = PersonalReferralRepository();
    repository.snapshot['public_enabled'] = true;
    await show(tester, repository);
    await tester.tap(find.text('SKOアプリ招待・自分の紹介履歴'));
    await tester.pumpAndSettle();
    expect(find.byType(AppReferralPage), findsOneWidget);
  });
  testWidgets('missing URL permits personal history but disables SMS preparation', (tester) async {
    final repository = PersonalReferralRepository();
    repository.snapshot['distribution_url_ready'] = false;
    await show(tester, repository);
    expect(find.textContaining('履歴の確認のみ可能'), findsOneWidget);
    await tester.tap(find.text('SKOアプリ招待・自分の紹介履歴'));
    await tester.pumpAndSettle();
    expect(find.byType(AppReferralPage), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '送信')).onPressed, isNull);
  });
  testWidgets('OFF and denied account cannot navigate', (tester) async {
    final repository = PersonalReferralRepository();
    repository.snapshot['enabled'] = false;
    await show(tester, repository);
    expect(find.textContaining('招待機能はOFF'), findsOneWidget);
    await tester.tap(find.text('SKOアプリ招待・自分の紹介履歴'));
    await tester.pumpAndSettle();
    expect(find.byType(AppReferralPage), findsNothing);
    repository.deny = true;
    await tester.tap(find.text('利用状態を再確認'));
    await tester.pumpAndSettle();
    expect(find.textContaining('利用権限・ログイン情報'), findsOneWidget);
  });
  testWidgets('opening rechecks permission and actor before navigation', (tester) async {
    for (final actorChange in [false, true]) {
      final repository = PersonalReferralRepository()
        ..disableOnOpen = !actorChange
        ..changeActor = actorChange;
      await show(tester, repository);
      await tester.tap(find.text('SKOアプリ招待・自分の紹介履歴'));
      await tester.pumpAndSettle();
      expect(find.byType(AppReferralPage), findsNothing);
      expect(repository.loads, 2);
      await tester.pumpWidget(const SizedBox());
    }
  });
}

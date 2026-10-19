import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/referrals/app_referral_master_entry.dart';
import 'package:sk_works/features/referrals/app_referral_page.dart';
import 'package:sk_works/features/referrals/app_referral_repository.dart';
import 'package:sk_works/features/settings/master_protected_page.dart';

class FakeReferralRepository implements AppReferralRepository {
  @override
  Stream<String?> watchActorChanges() => const Stream.empty();
  // These navigation fixtures only read snapshots; constructing an unused SDK
  // client would introduce token timers and asynchronous network disposal.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  bool denied = false;
  bool disableOnOpen = false;
  bool switchActorOnOpen = false;
  int loads = 0;
  String actor = 'master-user';
  final snapshot = <String, dynamic>{
    'enabled': false, 'public_enabled': false, 'can_invite': false,
    'distribution_url_ready': false,
  };
  @override
  String? get currentActorId => actor;
  @override
  Future<Map<String, dynamic>> load({bool master = false}) async {
    expect(master, isTrue);
    loads++;
    if (denied) {
      throw StateError('master required');
    }
    if (loads > 1 && disableOnOpen) {
      snapshot['enabled'] = false;
      snapshot['can_invite'] = false;
    }
    if (loads > 1 && switchActorOnOpen) {
      actor = 'another-user';
    }
    return Map<String, dynamic>.from(snapshot);
  }
}

Future<void> show(WidgetTester tester, FakeReferralRepository repository) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: AppReferralMasterEntry(repository: repository),
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('initial OFF keeps master settings and hides invitation', (tester) async {
    await show(tester, FakeReferralRepository());
    expect(find.text('招待機能：OFF（初期状態）'), findsOneWidget);
    expect(find.text('紹介設定・全体履歴'), findsOneWidget);
    expect(find.text('SKOアプリ招待'), findsNothing);
    expect(find.textContaining('正式な配布URLが未登録'), findsOneWidget);
  });
  testWidgets('denied master snapshot exposes no settings or invite route', (tester) async {
    await show(tester, FakeReferralRepository()..denied = true);
    expect(find.text('紹介設定・全体履歴'), findsNothing);
    expect(find.text('SKOアプリ招待'), findsNothing);
    expect(find.textContaining('Master権限'), findsOneWidget);
  });
  testWidgets('settings navigation retains existing master protection', (tester) async {
    await show(tester, FakeReferralRepository());
    await tester.tap(find.text('紹介設定・全体履歴'));
    await tester.pumpAndSettle();
    expect(find.byType(MasterProtectedPage), findsOneWidget);
    expect(find.byType(AppReferralPage), findsNothing);
  });
  testWidgets('OFF recheck suppresses a previously enabled invite', (tester) async {
    final repository = FakeReferralRepository()..disableOnOpen = true;
    repository.snapshot.addAll({'enabled': true, 'can_invite': true});
    await show(tester, repository);
    await tester.tap(find.text('SKOアプリ招待'));
    await tester.pumpAndSettle();
    expect(find.byType(MasterProtectedPage), findsNothing);
    expect(find.text('SKOアプリ招待'), findsNothing);
    expect(repository.loads, 2);
  });
  testWidgets('actor changed during recheck cannot open settings', (tester) async {
    await show(tester, FakeReferralRepository()..switchActorOnOpen = true);
    await tester.tap(find.text('紹介設定・全体履歴'));
    await tester.pumpAndSettle();
    expect(find.byType(MasterProtectedPage), findsNothing);
    expect(find.text('紹介設定・全体履歴'), findsNothing);
  });
}

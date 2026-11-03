import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/profile/personal_details_page.dart';
import 'package:sk_works/features/profile/personal_details_repository.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';
import 'personal_details_page_test.dart' as fixture;

class _PersonalGateway extends fixture.Gateway {
  int reads = 0;
  @override
  Future<PersonalDetailsSummary> load() async => const PersonalDetailsSummary(
    revision: 1,
    exists: true,
    bankRegistered: true,
    birthDate: '1990-01-02',
  );
  @override
  Future<OwnBankAccountInput?> readBank(
    int revision,
    PersonalProof proof,
  ) async {
    reads++;
    if (await proof('personal.bank.read', <String, dynamic>{
          'user_id': actorId,
          'revision': revision,
        }) ==
        null) {
      return null;
    }
    return OwnBankAccountInput(
      bankName: 'SYNTHETIC BANK',
      branchName: 'SYNTHETIC BRANCH',
      accountType: '普通',
      accountNumber: '1234567',
      accountHolder: 'SYNTHETIC OWNER',
    );
  }
}

void main() {
  testWidgets(
    'embedded personal fields remain usable beside company loading; bank contents still require proof',
    (t) async {
      final gateway = _PersonalGateway();
      var proofs = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const CircularProgressIndicator(value: .5),
                const Text('Synthetic company information loading'),
                PersonalDetailsPage(
                  embedded: true,
                  gateway: gateway,
                  requestProof: (_, __) async {
                    proofs++;
                    return 'synthetic-proof';
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byKey(const Key('personal-birth-date')), findsOneWidget);
      expect(gateway.reads, 0);
      expect(find.text('SYNTHETIC BANK'), findsNothing);
      await t.ensureVisible(find.text('本人確認して口座を表示'));
      await t.tap(find.text('本人確認して口座を表示'));
      await t.pumpAndSettle();
      expect(proofs, 1);
      expect(gateway.reads, 1);
      expect(find.text('SYNTHETIC BANK'), findsOneWidget);
      expect(gateway.writes, 0);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow embedded section clears personal fields when its session retires',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final gateway = _PersonalGateway();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                const Text('Synthetic company data unavailable'),
                PersonalDetailsPage(embedded: true, gateway: gateway),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('personal-birth-date')), findsOneWidget);
      expect(t.takeException(), isNull);
      gateway.retire();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('personal-birth-date')), findsNothing);
      expect(find.text('ログイン状態が変わりました。画面を開き直してください。'), findsOneWidget);
      expect(gateway.reads, 0);
      expect(gateway.writes, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}

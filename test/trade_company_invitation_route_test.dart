import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/companies/trade_company_invitation_page.dart';
import 'package:sk_works/features/companies/trade_company_repository.dart';

void main() {
  final code = 'a' * 48;

  test('Work Pass approval opens its own registration page', () {
    final link = companySignupInvitationLink(code, workPass: true);
    expect(link.fragment, '/?work_pass_invite=$code');
    expect(readTradeCompanyInvitation(link), (
      code: code,
      title: workPassInvitationTitle,
    ));
  });

  test('each company invite route retains its destination', () {
    for (final (mode, title) in [
      ('customer', '取引会社への招待'),
      ('subcontractor', '協力会社への招待'),
    ]) {
      final uri = Uri.https(
        'app.skojapan.com',
        '/',
      ).replace(fragment: '/?${mode}_invite=$code');
      expect(readTradeCompanyInvitation(Uri.parse(uri.toString())), (
        code: code,
        title: title,
      ));
      expect(uri.query, isEmpty);
    }
  });

  test(
    'ordinary sign in and invalid fragments are not company invitations',
    () {
      expect(
        readTradeCompanyInvitation(Uri.https('app.skojapan.com', '/')),
        isNull,
      );
      expect(
        readTradeCompanyInvitation(
          Uri.parse('https://app.skojapan.com/#/?customer_invite=invalid'),
        ),
        isNull,
      );
    },
  );
  for (final mode in TradeCompanyPageMode.values) {
    testWidgets('initial invite sends ${mode.name} and the existing company ID', (
      tester,
    ) async {
      final requests = <Map<String, dynamic>>[];
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://trade-invite-fixture.invalid',
          'fixture-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            if (request.url.path != '/rest/v1/rpc/prepare_trade_company_invitation') {
              throw StateError('Unexpected invitation endpoint');
            }
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode(code),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request,
            );
          }),
        ),
      ))!;
      addTearDown(client.dispose);
      await tester.pumpWidget(MaterialApp(
        home: TradeCompanyInvitationPage(
          client: client,
          contact: TradeCompanyRecord.fromJson({
            'id': 'existing-directory-id',
            'name': '連携先',
            'trade_role': 'both',
            'representative_phone': '09012345678',
          }),
          mode: mode,
        ),
      ));
      await tester.tap(find.text('招待リンクを発行'));
      await tester.pumpAndSettle();
      expect(requests.single['p_trade_company_id'], 'existing-directory-id');
      expect(requests.single['p_sender_role'], mode.name);
      expect(find.text('招待リンクをコピー'), findsOneWidget);
    });
  }
  for (final (title, localRole, senderLabel, recipientLabel) in [
    ('取引会社への招待', 'subcontractor', '協力会社', '取引会社'),
    ('協力会社への招待', 'customer', '取引会社', '協力会社'),
  ]) {
    testWidgets('$title exposes completion only after approval', (
      tester,
    ) async {
      final requests = <bool>[];
      var completed = false;
      var directoryOpened = false;
      final continueLabel = kIsWeb ? 'このままWebで使う' : '⑤ 完了して進む';
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://trade-invite-fixture.invalid',
          'fixture-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            if (request.url.path != '/rest/v1/rpc/trade_company_invitation') {
              throw StateError('Unexpected invitation endpoint');
            }
            final accept = jsonDecode(request.body)['p_accept'] as bool;
            requests.add(accept);
            return http.Response(
              jsonEncode({
                'accepted': accept,
                'sender': '招待元テスト',
                'receiver': '受け手テスト',
                'local_role': localRole,
                'start_month': '2026-11-01',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request,
            );
          }),
        ),
      ))!;
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TradeCompanyInvitationAcceptancePage(
            client: client,
            code: code,
            title: title,
            onDone: () => completed = true,
            onOpenDirectory: () => directoryOpened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, [false]);
      expect(find.text('④ 会社の関係を確認'), findsOneWidget);
      expect(find.text('自社から見た関係　$senderLabel'), findsOneWidget);
      expect(find.text(continueLabel), findsNothing);
      expect(find.text('連携会社登録を開く'), findsNothing);

      await tester.tap(find.text('④ 承認して連携する'));
      await tester.pumpAndSettle();
      expect(requests, [false, true]);
      expect(find.text('連携が完了しました'), findsOneWidget);
      expect(find.textContaining('双方の「連携会社登録」'), findsOneWidget);
      expect(find.textContaining('相手側では自社が「$recipientLabel」'), findsOneWidget);
      await tester.ensureVisible(find.text('連携会社登録を開く'));
      await tester.tap(find.text('連携会社登録を開く'));
      expect(directoryOpened, isTrue);

      await tester.ensureVisible(find.text(continueLabel));
      await tester.tap(find.text(continueLabel));
      expect(completed, isTrue);
    });
  }
}

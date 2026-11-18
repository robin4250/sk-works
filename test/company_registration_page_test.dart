import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/settings/company_registration_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('company submits Work Pass under its selected company', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? submitted;
    final client = SupabaseClient(
      'https://company-fixture.invalid',
      'public-fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/submit_company_registration')) {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 204, request: request);
        }
        return http.Response(
          jsonEncode({
            'companies': [{'id': 'company-a', 'name': 'Fixture Company'}],
            'requests': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.auth.dispose);
    await tester.pumpWidget(MaterialApp(home: CompanyRegistrationPage(client: client)));
    await tester.pumpAndSettle();

    expect(find.text('申請の読み込みに失敗しました。'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ワークパス').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('会社から申請する'));
    await tester.tap(find.text('会社から申請する'));
    await tester.pumpAndSettle();
    final nameError = tester.getRect(find.text('氏名を入力してください。'));
    final phoneField = tester.getRect(find.byType(TextFormField).at(1));
    expect(phoneField.top - nameError.bottom, greaterThanOrEqualTo(12));
    await tester.enterText(find.byType(TextFormField).at(0), '登録対象者');
    await tester.enterText(find.byType(TextFormField).at(1), '090-0000-0001');
    await tester.ensureVisible(find.text('会社から申請する'));
    await tester.tap(find.text('会社から申請する'));
    await tester.pumpAndSettle();

    expect(submitted, {
      'p_company_id': 'company-a',
      'p_purpose': 'work_pass',
      'p_person_name': '登録対象者',
      'p_phone': '+819000000001',
    });
    expect(find.text('承認'), findsNothing);
  });

  testWidgets('master reviews a Work Pass request and sees a dedicated link after confirming', (tester) async {
    Map<String, dynamic>? reviewed;
    final code = 'b' * 48;
    final client = SupabaseClient(
      'https://master-fixture.invalid',
      'public-fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/review_company_registration')) {
          reviewed = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(code), 200, headers: {'content-type': 'application/json'}, request: request);
        }
        return http.Response(jsonEncode({
          'companies': [],
          'requests': [{
            'id': 'request-a',
            'company_name': 'Fixture Company',
            'person_name': '登録対象者',
            'phone': '+819000000001',
            'purpose': 'work_pass',
            'decision': 'pending',
            'registered': false,
          }],
        }), 200, headers: {'content-type': 'application/json'}, request: request);
      }),
    );
    addTearDown(client.auth.dispose);
    await tester.pumpWidget(MaterialApp(home: CompanyRegistrationPage(client: client, review: true)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Fixture Company　ワークパス'), findsOneWidget);
    await tester.tap(find.text('承認'));
    await tester.pumpAndSettle();
    expect(reviewed, isNull);
    expect(find.textContaining('本人と電話番号を個別に確認'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '承認').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reviewed, {'p_request_id': 'request-a', 'p_action': 'approve'});
    expect(find.text('ワークパス登録リンク'), findsOneWidget);
    expect(find.text('招待リンクをコピー'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });
}

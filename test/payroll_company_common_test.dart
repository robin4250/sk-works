import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payroll_company_common_card.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

const commonId = '70000000-0000-0000-0000-000000000001';
Map<String, dynamic> item({String unit = 'hour', num? quantity}) => {
  'id': commonId, 'origin': 'company_common', 'section': 'earning',
  'unit': unit, 'name': '共通手当', 'rate_yen': 100,
  'quantity': quantity, 'amount_yen': quantity == null ? null : (quantity * 100).round(),
  'quantity_month': '2026-10-01',
};
Map<String, dynamic> response({num? quantity}) => {
  'version': 0, 'month': '2026-10-01', 'can_edit': true, 'items': [],
  'company_common': {'contract_version': 1, 'items': [item(quantity: quantity)],
    'source': {'starts_on': '2026-10-01', 'pay_type': 'monthly', 'items': [item(quantity: quantity)]}},
};
void main() {
  test('missing effective history stays explicit even without common rows', () {
    final value = response();
    value['company_common'] = {'contract_version': 1, 'items': [], 'source': {}, 'history_missing': true};
    final parsed = PayrollUnitConditions.fromJson(value);
    expect(parsed.companyCommonHistoryMissing, isTrue);
    expect(parsed.companyCommonItems, isEmpty);
    value['company_common']['frozen'] = true;
    value['company_common']['history_missing'] = false;
    expect(PayrollUnitConditions.fromJson(value).companyCommonFrozen, isTrue);
  });

  test('legacy response remains compatible; mismatched common month fails closed', () {
    expect(PayrollUnitConditions.fromJson({'version': 0, 'month': '2026-10-01', 'can_edit': true, 'items': []}).companyCommonItems, isEmpty);
    final bad = response();
    ((bad['company_common'] as Map)['items'] as List).first['quantity_month'] = '2026-09-01';
    expect(() => PayrollUnitConditions.fromJson(bad), throwsStateError);
  });
  for (final mode in ['valid', 'same_token_signout_signin', 'wrong_month']) {
    test('common hours real SDK RPC: $mode', () async {
      const uid = '00000000-0000-0000-0000-000000000001';
      final user = {'id': uid, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'fixture@example.invalid', 'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}};
      String part(Object x) => base64Url.encode(utf8.encode(jsonEncode(x))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      final calls = <Map<String, dynamic>>[];
      late SupabaseClient client;
      client = SupabaseClient('https://fixture.invalid', 'public-fixture', authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((request) async {
        Object? value;
        if (request.url.path == '/auth/v1/token') {
          value = {'access_token': token, 'refresh_token': 'fixture', 'token_type': 'bearer', 'expires_in': 3600, 'user': user};
        } else if (request.url.path == '/rest/v1/rpc/save_payroll_common_hours') {
          expect(request.headers['Authorization'], 'Bearer $token');
          calls.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
          if (mode == 'same_token_signout_signin') {
            await client.auth.signOut(scope: SignOutScope.local);
            await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
          }
          value = response(quantity: 2.5);
          if (mode == 'wrong_month') (value as Map)['month'] = '2026-09-01';
        } else if (request.url.path == '/auth/v1/logout') {
          return http.Response('', 204, request: request);
        } else {
          throw StateError('unexpected request');
        }
        return http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
      final repository = PayrollUnitConditionsRepository(client);
      final current = PayrollUnitConditions.fromJson(response());
      final future = repository.saveCommonHours('company-fixture', 'worker-fixture', current, {commonId: '2.5'});
      if (mode == 'valid') {
        expect((await future).companyCommonItems.single['quantity'], 2.5);
      } else {
        await expectLater(future, throwsStateError);
      }
      expect(calls.single['p_expected_source'], jsonDecode(current.companyCommonSourceJson!));
      expect(calls.single['p_hours'], [{'id': commonId, 'quantity': '2.5'}]);
    });
  }
  testWidgets('common hours require explicit input; zero is saved without changing rate', (tester) async {
    Map<String, String>? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollCompanyCommonCard(
      items: [item()], canEdit: true, onSave: (hours) async { saved = hours; }, onReload: () {},
    ))));
    await tester.tap(find.text('社内共通手当')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('common-hours-save'))); await tester.pumpAndSettle();
    expect(saved, isNull); expect(find.text('時間数を0以上の数値で入力してください'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.byKey(const ValueKey('common-hours-save'))); await tester.pumpAndSettle();
    expect(saved, {commonId: '0'}); expect(find.text('共通手当  ¥100'), findsOneWidget);
  });
  testWidgets('viewer sees monthly common amount without edit or save controls', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PayrollCompanyCommonCard(
      items: [item(unit: 'month', quantity: 1)], canEdit: false,
      section: PayrollItemSection.earning, unit: PayrollItemUnit.month,
      onSave: (_) async { fail('viewer save'); }, onReload: () {},
    ))));
    await tester.tap(find.text('社内共通手当')); await tester.pumpAndSettle();
    expect(find.text('共通手当  ¥100'), findsOneWidget); expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('common-hours-save')), findsNothing);
  });
}

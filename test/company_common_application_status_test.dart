import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/company_common_application_status.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_page.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';
import 'package:sk_works/features/payroll/payroll_unit_item_editor.dart';

String source({String? startsOn, String? type = 'daily', Object? version}) => jsonEncode({
  'starts_on': startsOn, 'pay_type': type, 'publication_version': version,
  'items': <Object>[],
});

CompanyCommonApplicationStatus? status(String? json, {
  bool frozen = false, bool historyMissing = false, bool hasItems = false,
  bool blocked = false,
}) => companyCommonApplicationStatus(sourceJson: json, month: '2026-10-01',
  frozen: frozen, historyMissing: historyMissing, hasItems: hasItems, blocked: blocked);

void main() {
  test('registered company rates do not imply a payroll application date', () {
    expect(status(source()), CompanyCommonApplicationStatus.notRegistered);
    expect(status(source(startsOn: '2026-11-01')), CompanyCommonApplicationStatus.startsLater);
    expect(status(source(startsOn: '2026-10-01')), isNull);
    expect(status(source(startsOn: '2026-09-01', version: 2)), isNull);
  });

  test('missing, older or unknown reader sources are not called unregistered', () {
    for (final json in <String?>[null, '{}', 'null', 'broken',
      source(type: null), source(type: 'unknown'), source(startsOn: 'bad')]) {
      expect(status(json), isNull);
    }
  });

  test('finalized, blocked, history-missing and effective item states retain their own display', () {
    expect(status(source(), frozen: true), isNull);
    expect(status(source(), blocked: true), isNull);
    expect(status(source(), historyMissing: true), isNull);
    expect(status(source(), hasItems: true), isNull);
  });

  testWidgets('empty monthly individual panel exposes unregistered application without a write', (tester) async {
    final requests = <http.Request>[];
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final transport = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/payroll_unit_conditions_contract_version')) {
        return http.Response('1', 200, headers: {'content-type': 'application/json'});
      }
      expect(request.url.path.endsWith('/payroll_unit_conditions'), isTrue);
      return http.Response(jsonEncode({
        'version': 0, 'month': month, 'can_edit': false, 'items': <Object>[],
        'company_common': {'contract_version': 1, 'history_missing': false,
          'frozen': false, 'items': <Object>[], 'source': jsonDecode(source())},
      }), 200, headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture-key', httpClient: transport);
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: PayrollUnitConditionsPage(
        repository: PayrollUnitConditionsRepository.forTesting(client, () => 'fixture-actor'),
        companyId: 'fixture-company', workerId: 'fixture-worker', embedded: true,
        section: PayrollItemSection.earning, unit: PayrollItemUnit.month,
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('company-common-application-status')), findsOneWidget);
    expect(find.text('この給与形態の適用開始月は未登録です。社内共通手当で対象を確認して反映してください。'), findsOneWidget);
    expect(requests.length, 2);
    expect(tester.takeException(), isNull);
  });
}

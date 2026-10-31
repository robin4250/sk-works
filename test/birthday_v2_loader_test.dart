import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/people_page.dart';
import 'package:sk_works/features/people/people_cloud_repository.dart';
import 'package:sk_works/features/people/employee_personnel_edit_page.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

const company = '60000000-0000-0000-0000-000000000010';
const worker = '60000000-0000-0000-0000-000000000020';
const digest = '0123456789abcdef0123456789abcdef';

void main() {
  for (final invalid in [
    {'root': 1, 'row': 2, 'digest': digest},
    {'root': 2, 'row': 1, 'digest': digest},
    {'root': 2, 'row': 2, 'digest': 'malformed'},
  ]) {
    test('mismatched capability cannot survive the SDK reader: $invalid', () async {
      final wire = fixture.Wire();
      await wire.seed();
      addTearDown(wire.client.dispose);
      wire.respond = (request) async {
        if (request.url.path.endsWith('/company_members')) {
          return fixture.Wire.json([{'company_id': company, 'role': 'admin'}]);
        }
        if (request.url.path.endsWith('/rpc/employee_personnel_view')) {
          return fixture.Wire.json({
          'company_id': company, 'birth_date_contract_version': invalid['root'],
          'records': [{'id': worker, 'name': 'Synthetic employee', 'active': true,
            'birthDate': '1980-02-29', 'birthDateContractVersion': invalid['row'],
            'personnelCasDigest': invalid['digest']}],
        });
        }
        throw StateError('Unexpected synthetic SDK endpoint');
      };
      final snapshot = await PeopleCloudRepository.forClient(wire.client).readPersonnel(expectedCompany: company);
      final record = PersonRecord.fromJson(snapshot.records.single);
      expect(record.birthDate, '1980-02-29');
      expect(record.birthDateContractVersion, 0);
      expect(record.personnelCasDigest, isEmpty);
    });
  }
  testWidgets('actual SDK loader mapping keeps initial CAS through DTO, editor and narrow save', (t) async {
    final wire = fixture.Wire();
    debugPrint('DOB_LOADER seed-start');
    await t.runAsync(wire.seed);
    debugPrint('DOB_LOADER seed-complete');
    addTearDown(() async {
      debugPrint('DOB_LOADER teardown-widget-start');
      await t.pumpWidget(const SizedBox.shrink());
      debugPrint('DOB_LOADER teardown-widget-complete');
      await t.runAsync(wire.client.dispose);
      debugPrint('DOB_LOADER teardown-client-complete');
    });
    Map<String, dynamic>? saved;
    wire.respond = (request) async {
      final path = request.url.path;
      debugPrint('DOB_LOADER request $path');
      if (path.endsWith('/company_members')) {
        return fixture.Wire.json([{'company_id': company, 'role': 'admin'}]);
      }
      if (path.endsWith('/rpc/people_management_records')) {
        return fixture.Wire.json([
        {'id': worker, 'kind': 'employee', 'name': 'Old roster name', 'role': 'Old roster role', 'active': true},
      ]);
      }
      if (path.endsWith('/rpc/employee_personnel_view')) {
        return fixture.Wire.json({
        'company_id': company, 'birth_date_contract_version': 2, 'records': [
          {'id': worker, 'name': 'Canonical employee', 'kind': 'employee', 'role': 'Canonical role',
            'active': true, 'birthDate': '1980-02-29', 'birthDateContractVersion': 2,
            'personnelCasDigest': digest, 'familyMembers': [
              {'id': '60000000-0000-0000-0000-000000000030', 'name': 'Child', 'relation': '子', 'birth_date': '2020-01-01', 'is_dependent': false},
            ]},
        ],
      });
      }
      if (path.endsWith('/workers')) {
        return fixture.Wire.json([{'id': worker}]);
      }
      if (path.endsWith('/partner_companies') || path.endsWith('/rpc/list_employee_categories')) {
        return fixture.Wire.json([]);
      }
      if (path.endsWith('/rpc/ensure_employee_categories')) {
        return fixture.Wire.json({});
      }
      if (path.endsWith('/rpc/save_worker_personnel_profile')) {
        saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return fixture.Wire.json({'status': 'saved', 'requires_approval': false, 'saved_directly': true});
      }
      throw StateError('Unexpected synthetic SDK endpoint: $path');
    };
    final repository = PeopleCloudRepository.forClient(wire.client);
    debugPrint('DOB_LOADER load-start');
    final rows = (await t.runAsync(() => repository.loadAll(expectedCompany: company)))!;
    debugPrint('DOB_LOADER load-complete');
    final record = PersonRecord.fromJson(rows.single);
    expect(record.personnelCasDigest, digest);
    expect(record.name, 'Canonical employee');
    expect(record.role, 'Canonical role');
    debugPrint('DOB_LOADER widget-pump-start');
    await t.pumpWidget(MaterialApp(home: EmployeePersonnelEditPage(record: record, repository: repository)));
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER widget-settled');
    final birthdayTile = find.ancestor(of: find.text('生年月日'), matching: find.byType(ListTile)).first;
    expect(t.widget<ListTile>(birthdayTile).onTap, isNotNull);
    debugPrint('DOB_LOADER birthday-visible-start');
    await t.ensureVisible(find.byTooltip('生年月日を未登録に戻す'));
    debugPrint('DOB_LOADER birthday-visible-complete');
    await t.tap(find.byTooltip('生年月日を未登録に戻す'));
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER clear-settled');
    final save = find.widgetWithText(FilledButton, '保存する');
    await t.ensureVisible(save);
    debugPrint('DOB_LOADER save-visible');
    await t.tap(save);
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER confirm-dialog-settled');
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, '保存する')));
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER save-observed');
    expect(saved, isNotNull);
    expect(saved!['p_worker_id'], worker);
    final payload = saved!['p_payload'] as Map;
    expect(payload['birth_date'], isNull);
    expect(payload['_birth_date_mode'], 'only');
    expect(payload.containsKey('family_members'), isFalse);
    expect(payload.containsKey('name'), isFalse);
    expect((payload['_birth_date_cas'] as Map)['expected_birth_date'], '1980-02-29');
    expect((payload['_birth_date_cas'] as Map)['expected_personnel_digest'], digest);
    debugPrint('DOB_LOADER body-complete');
    await t.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 45)));
}

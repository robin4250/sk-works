import 'dart:async';
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
  for (final unknown in [false, true]) {
  testWidgets('actual SDK loader mapping retains CAS and handles unknown=$unknown', (t) async {
    debugPrint('DOB_LOADER sdk-construction-start');
    final wire = (await t.runAsync(() async => fixture.Wire()))!;
    debugPrint('DOB_LOADER sdk-construction-complete');
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
    var saveCount = 0;
    final dispatched = Completer<void>();
    final editReturned = Completer<bool?>();
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
        saveCount++;
        dispatched.complete();
        if (unknown) { return fixture.Wire.json({}); }
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
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () {
        Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) =>
          EmployeePersonnelEditPage(record: record, repository: repository))).then(editReturned.complete);
      }, child: const Text('Open synthetic employee editor'))))));
    await t.tap(find.text('Open synthetic employee editor'));
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER widget-settled');
    final birthdayTile = find.ancestor(of: find.text('生年月日'), matching: find.byType(ListTile)).first;
    expect(t.widget<ListTile>(birthdayTile).onTap, isNotNull);
    if (unknown) {
      final nameField = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == '名前');
      await t.scrollUntilVisible(nameField, -500, scrollable: find.byType(Scrollable).first);
      await t.enterText(nameField, 'Unsaved draft name');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
    }
    debugPrint('DOB_LOADER birthday-visible-start');
    await t.ensureVisible(find.byTooltip('生年月日を未登録に戻す'));
    debugPrint('DOB_LOADER birthday-visible-complete');
    await t.tap(find.byTooltip('生年月日を未登録に戻す'));
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER clear-settled');
    final save = find.text('保存する');
    await t.scrollUntilVisible(save, 500, scrollable: find.byType(Scrollable).first);
    debugPrint('DOB_LOADER save-visible');
    await t.tap(save);
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER confirm-dialog-settled');
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, '保存する')));
    await t.pumpAndSettle();
    debugPrint('DOB_LOADER save-dispatch-await');
    // UI started the SDK work in the fake zone: drive both fake timers and
    // real SDK events rather than freezing fake time while awaiting its Future.
    Future<void> driveUntil(bool Function() done, String stage) async {
      for (var step = 0; step < 100 && !done(); step++) {
        await t.pump(const Duration(milliseconds: 20));
        await t.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(done(), isTrue, reason: stage);
    }
    await driveUntil(() => dispatched.isCompleted, 'actual SDK POST must arrive');
    debugPrint('DOB_LOADER save-dispatched');
    if (unknown) {
      bool saveRetired() {
        final labels = find.text('保存する');
        final buttons = find.ancestor(of: labels, matching: find.byWidgetPredicate((widget) => widget is FilledButton));
        return buttons.evaluate().any((element) => (element.widget as FilledButton).onPressed == null);
      }
      await driveUntil(saveRetired, 'unknown must retire the same form');
      expect(editReturned.isCompleted, isFalse);
      await t.tap(find.text('保存する'), warnIfMissed: false);
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(saveCount, 1, reason: 'unknown result must not resubmit');
      const review = '入力内容を保持しています。一覧を更新して保存結果を確認してください。';
      await t.scrollUntilVisible(find.text(review), -500, scrollable: find.byType(Scrollable).first);
      expect(t.widget<ListTile>(find.ancestor(of: find.text('生年月日'), matching: find.byType(ListTile)).first).onTap, isNull);
      final nameField = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == '名前');
      await t.scrollUntilVisible(nameField, -500, scrollable: find.byType(Scrollable).first);
      expect(t.widget<TextField>(nameField).controller!.text, 'Unsaved draft name');
      debugPrint('DOB_LOADER unknown-retired-draft-retained');
    } else {
      await driveUntil(() => editReturned.isCompleted, 'editor save result must return');
      final savedResult = await editReturned.future;
      debugPrint('DOB_LOADER editor-result-returned');
      await t.pumpAndSettle();
      expect(savedResult, isTrue);
    }
    expect(saved, isNotNull);
    expect(saved!['p_worker_id'], worker);
    final payload = saved!['p_payload'] as Map;
    expect(payload['birth_date'], isNull);
    expect(payload['_birth_date_mode'], unknown ? 'combined' : 'only');
    expect(payload.containsKey('family_members'), unknown);
    expect(payload.containsKey('name'), unknown);
    expect((payload['_birth_date_cas'] as Map)['expected_birth_date'], '1980-02-29');
    expect((payload['_birth_date_cas'] as Map)['expected_personnel_digest'], digest);
    debugPrint('DOB_LOADER body-complete');
    await t.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(seconds: 45)));
  }
}

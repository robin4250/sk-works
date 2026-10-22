import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/core/language_pack.dart';
import 'package:sk_works/features/payroll/company_common_allowance_repository.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_approval.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_command.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_panel.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_pending_store.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_repository.dart';
import 'package:sk_works/features/payroll/company_common_payroll_publication_surface.dart';
import 'support/common_canonical_client_fixture.dart' as fixture;

class _MemoryStore implements CommonPayrollCanonicalPublicationPendingStore {
  CommonPayrollCanonicalPublicationPending? value;
  @override Future<CommonPayrollCanonicalPublicationPending?> read(String actor, String company) async => value;
  @override Future<void> write(CommonPayrollCanonicalPublicationPending pending) async {
    if (value != null) throw StateError('existing pending');
    value = pending;
  }
  @override Future<void> clear(CommonPayrollCanonicalPublicationPending pending) async {
    if (value == null || canonicalPublicationJson(value!.toJson()) != canonicalPublicationJson(pending.toJson())) {
      throw StateError('different pending');
    }
    value = null;
  }
}

class _Repository extends fixture.FakeCanonicalRepository {
  _Repository(this.store);
  final _MemoryStore store;
  bool deployed = true;
  Completer<void>? held;
  CommonPayrollCanonicalPublicationCommand? submitted;
  @override Future<bool> available() async => deployed;
  @override Future<CommonPayrollCanonicalPublicationPreview> preview(Map<String, dynamic> params) async {
    final raw = fixture.previewJson()
      ..['command_base'] = params
      ..['scopes'] = [{...fixture.scope(), 'month': params['p_starts_on']}];
    return CommonPayrollCanonicalPublicationPreview.parse(raw, params);
  }
  Map<String, dynamic> result(CommonPayrollCanonicalPublicationCommand value) {
    final raw = fixture.resultJson()
      ..['request_id'] = value.requestId
      ..['starts_on'] = value.startsOn
      ..['payroll_type'] = value.payrollType;
    (raw['timeline'] as Map)['entries'] = [{'version': 1, 'payroll_type': value.payrollType,
      'starts_on': value.startsOn, 'request_id': value.requestId}];
    return raw;
  }
  @override Future<CommonPayrollCanonicalPublicationResult> publish(CommonPayrollCanonicalPublicationCommand value) async {
    publishes++; submitted = value;
    expect(store.value?.command.params, value.params);
    await held?.future;
    if (publishError != null) throw publishError!;
    return CommonPayrollCanonicalPublicationResult.parse(result(value), value);
  }
  @override Future<CommonPayrollCanonicalPublicationResult?> receipt(CommonPayrollCanonicalPublicationCommand value) async {
    receiptCommands.add(value.receiptParams);
    return found ? CommonPayrollCanonicalPublicationResult.parse(result(value), value) : null;
  }
}

CompanyCommonAllowanceState settings({bool legacy = false}) => CompanyCommonAllowanceState(
  companyId: fixture.company, version: 3, canEdit: true, items: const [],
  legacyRefs: [if (legacy) {'amount_yen': 1, 'name': '合成手当'}],
  expectedSource: const {'fixture_source': 'original'});

void main() {
  Future<void> mount(WidgetTester tester, _Repository repository, _MemoryStore store, {String key = 'panel'}) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CompanyCommonCanonicalPublicationPanel(
      key: ValueKey(key), settings: settings(), repository: repository, pendingStore: store,
      initialPayrollType: 'monthly',
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未確定給与への反映'));
    await tester.pumpAndSettle();
  }
  Future<VoidCallback> approve(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('canonical-publication-prepare')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('canonical-publication-activation')));
    await tester.tap(find.byKey(const ValueKey('canonical-publication-activation')));
    await tester.pumpAndSettle();
    return tester.widget<FilledButton>(find.byKey(const ValueKey('canonical-publication-confirm'))).onPressed!;
  }
  testWidgets('translated panel and approval format counts without changing request data', (tester) async {
    final previous = SkoLanguageController.pack.value;
    addTearDown(() => SkoLanguageController.pack.value = previous);
    SkoLanguageController.pack.value = const LanguagePack(languageCode: 'en', fallbackLanguageCode: 'ja', strings: {
      '未確定給与への反映': 'Apply to draft payroll',
      '共通手当を給与へ反映': 'Apply common allowances',
      '反映対象 {target}件　除外 {excluded}件　要確認 {unresolved}件':
        'Targets {target}, excluded {excluded}, review {unresolved}',
    });
    final store = _MemoryStore(); final repository = _Repository(store);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CompanyCommonCanonicalPublicationPanel(
      settings: settings(), repository: repository, pendingStore: store,
      initialPayrollType: 'monthly',
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply to draft payroll'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('canonical-publication-prepare')));
    await tester.pumpAndSettle();
    expect(find.text('Apply common allowances'), findsOneWidget);
    expect(find.text('Targets 1, excluded 0, review 0'), findsOneWidget);
    expect(repository.publishes, 0);
    expect(store.value, isNull);
  });
  testWidgets('one explicit approval persists before publish and repeated callback does not pop the page', (tester) async {
    final store = _MemoryStore();
    // Use the same store for the durability assertion inside the repository.
    final actual = _Repository(store);
    await mount(tester, actual, store);
    expect(actual.publishes, 0);
    final confirm = await approve(tester);
    expect(find.byType(CommonPayrollCanonicalPublicationApprovalDialog), findsOneWidget);
    confirm(); confirm();
    await tester.pumpAndSettle();
    expect(actual.publishes, 1);
    expect(store.value, isNull);
    expect(find.textContaining('未確定給与への反映を登録しました'), findsOneWidget);
  });
  testWidgets('recreated panel uses read-only lookup with the original request and never republishes', (tester) async {
    final store = _MemoryStore(); final repository = _Repository(store)..publishError = StateError('transport unknown');
    await mount(tester, repository, store);
    (await approve(tester))();
    await tester.pumpAndSettle();
    final original = store.value!.command.params;
    expect(repository.publishes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, repository, store, key: 'restored');
    await tester.tap(find.byKey(const ValueKey('canonical-publication-lookup')));
    await tester.pumpAndSettle();
    expect(store.value, isNotNull);
    expect(repository.receiptCommands.single['p_expected_command'], original);
    repository.found = true;
    await tester.tap(find.byKey(const ValueKey('canonical-publication-lookup')));
    await tester.pumpAndSettle();
    expect(store.value, isNull);
    expect(repository.publishes, 1);
  });
  testWidgets('resume during an in-flight publish drains it and restores lookup without another publish', (tester) async {
    final store = _MemoryStore(); final repository = _Repository(store)
      ..held = Completer<void>()..publishError = StateError('transport unknown');
    await mount(tester, repository, store);
    (await approve(tester))();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.publishes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    repository.held!.complete();
    await tester.pumpAndSettle();
    expect(repository.publishes, 1);
    final lookup = tester.widget<TextButton>(find.byKey(const ValueKey('canonical-publication-lookup')));
    expect(lookup.onPressed, isNotNull);
    expect(store.value, isNotNull);
  });
  testWidgets('unavailable new contract with positive legacy never falls back to the old apply action', (tester) async {
    final store = _MemoryStore(); final repository = _Repository(store)..deployed = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CompanyCommonPayrollPublicationSurface(
      settings: settings(legacy: true), repository: repository,
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未確定給与への反映'));
    await tester.pumpAndSettle();
    expect(find.text('共通手当の登録・保存は利用できます'), findsOneWidget);
    expect(find.byKey(const ValueKey('common-publication-apply')), findsNothing);
    expect(repository.publishes, 0);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_payroll_rates_repository.dart';
import 'package:sk_works/features/settings/initial_official_company_rates.dart';

class Rates extends Fake implements CompanyPayrollRatesRepository, OfficialCompanyPayrollRateFetcher {
  bool canEdit = true, failFetch = false, active = true, changeScope = false, incomplete = false, keepOld = false, existingDuringFetch = false;
  int fetches = 0, commits = 0, reads = 0;
  Map<String, String>? months;
  bool? committedFallback;
  Map<String, String>? committedIds;
  CompanyPayrollRateScope? scope = const CompanyPayrollRateScope(version: 1,
    value: {'insurer':'kyokai','prefecture':'東京都','employment_business':'construction'}, updatedBy: 'actor', updatedAt: '');
  List<CompanyPayrollRateItem> items = [];
  List<CompanyPayrollRateCandidate> candidates = [];
  @override
  Future<CompanyPayrollRatesData> read(String companyId) async {
    reads++;
    return CompanyPayrollRatesData(canEdit: canEdit, items: items, candidates: candidates, history: [], companyScope: scope);
  }
  @override
  Future<void> saveScope({required String companyId, required int expectedVersion, required Map<String,dynamic> value}) async {
    expect(expectedVersion,0);expect(scope,isNull);
    scope = CompanyPayrollRateScope(version:1,value:value,updatedBy:'actor',updatedAt:'');
  }
  @override
  Future<List<String>> fetchOfficial(String companyId, Map<String,String> value) async {
    fetches++; months=value;
    if (failFetch) throw StateError('offline or unsupported official year');
    if (changeScope) scope = const CompanyPayrollRateScope(version:2,value:{'insurer':'kyokai'},updatedBy:'actor',updatedAt:'');
    if (existingDuringFetch) items=[saved()];
    if (!keepOld) {
      candidates = [for(final kind in {...initialOfficialRateKinds,'child_support'})
      if (!(incomplete && kind=='employment_insurance'))
        CompanyPayrollRateCandidate(id:kind,itemId:kind,value:{'kind':kind,...value},checkedAt:'',scopeVersion:1)];
    }
    return [];
  }
  Future<bool> commit(int version, Map<String,String> ids, bool fallback) async {
    commits++;committedFallback=fallback;committedIds=ids;
    if (version != scope?.version) throw StateError('scope conflict');
    return true;
  }
  InitialOfficialCompanyRates initializer({DateTime? date}) => InitialOfficialCompanyRates(
    repository:this,fetcher:this,loadAddress:() async=>'東京都新宿区',commit:commit,isCurrent:()=>active,
    now:()=>date ?? DateTime(2026,10,11));
}
CompanyPayrollRateItem saved({bool fallback=false}) => CompanyPayrollRateItem(id:'health_insurance',version:1,origin:'manual',
  value:{'source':{'applicability':fallback ? {'initial_reference':'2026-10'} : {'confirmed':'yes'}}});

void main() {
  test('first use obtains current months and commits four fresh official values',() async {
    for(final date in [DateTime(2026,10),DateTime(2027,12),DateTime(2029,3)]) {
      final r=Rates(); expect(await r.initializer(date:date).run('company'),InitialOfficialRateResult.initialized);
      expect(r.months!['insurance_month'],'${date.year}-${date.month.toString().padLeft(2,'0')}-01');
      final next=DateTime(date.year,date.month+1);
      expect(r.months!['payment_month'],'${next.year}-${next.month.toString().padLeft(2,'0')}-01');
      expect(r.committedIds!.keys.toSet(),initialOfficialRateKinds);expect(r.committedFallback,false);
    }
  });
  test('missing scope uses registered prefecture and requested kenpo/construction defaults',() async {
    final r=Rates()..scope=null;await r.initializer().run('company');
    expect(r.scope!.value,{'insurer':'kyokai','prefecture':'東京都','employment_business':'construction'});
  });
  test('fetch failure uses labelled reference path once, not fabricated official values',() async {
    final r=Rates()..failFetch=true;
    expect(await r.initializer().run('company'),InitialOfficialRateResult.fallback);
    expect(r.commits,1);expect(r.committedFallback,true);expect(r.committedIds,isEmpty);
  });
  test('incomplete or old candidates fall back instead of partially applying rates',() async {
    for(final r in [Rates()..incomplete=true,Rates()..keepOld=true]) {
      expect(await r.initializer().run('company'),InitialOfficialRateResult.fallback);
      expect(r.committedIds,isEmpty);
    }
  });
  test('existing official/manual/reference values do not fetch or overwrite',() async {
    for(final fallback in [false,true]) {
      final r=Rates()..items=[saved(fallback:fallback)];
      expect(await r.initializer().run('company'),fallback ? InitialOfficialRateResult.fallback : InitialOfficialRateResult.preserved);
      expect(r.fetches,0);expect(r.commits,0);
    }
  });
  test('viewer and concurrently saved rates cause no writes',() async {
    for(final r in [Rates()..canEdit=false,Rates()..existingDuringFetch=true]) {
      expect(await r.initializer().run('company'),InitialOfficialRateResult.preserved);expect(r.commits,0);
    }
  });
  test('scope conflict and actor change never overwrite company values',() async {
    final r=Rates()..changeScope=true;await expectLater(r.initializer().run('company'),throwsStateError);
    final signedOut=Rates()..active=false;await expectLater(signedOut.initializer().run('company'),throwsStateError);
    expect(signedOut.reads,0);expect(signedOut.commits,0);
  });
}

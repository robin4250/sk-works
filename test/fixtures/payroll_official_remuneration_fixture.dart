import 'package:sk_works/features/payroll/payroll_standard_remuneration.dart';

Map<String, dynamic> officialTableRate({bool pension = false}) => {
  'kind': pension ? 'pension_insurance' : 'health_insurance',
  'source': {'applicability': <String, dynamic>{
    'remuneration_table_version': 'jp-general-2026-v1',
    'remuneration_bases_csv': (pension ?
        PayrollStandardRemuneration.healthBases.sublist(3, 35) :
        PayrollStandardRemuneration.healthBases).join(','),
    'remuneration_lower_bounds_csv': (pension ?
        [0, ...PayrollStandardRemuneration.lowerBounds.sublist(4, 35)] :
        PayrollStandardRemuneration.lowerBounds).join(','),
    'remuneration_source_url': 'https://www.kyoukaikenpo.or.jp/lp/2026hokenryou/',
    'remuneration_document_hash': 'a' * 64,
    'remuneration_effective_from': pension ? '2020-09-01' : '2026-03-01',
    if (pension) 'remuneration_verification_url': 'https://www.nenkin.go.jp/service/yougo/hagyo/hyojunhoshugetsu.html',
    if (pension) 'remuneration_verification_hash': 'b' * 64,
  }},
};

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/company_work_category_policy.dart';
import 'package:sk_works/features/settings/company_work_category_repository.dart';

void main() {
  final policy = CompanyWorkCategoryPolicy.parse({
    'schema': 1, 'night_start_minute': 1320, 'night_end_minute': 300,
    'holiday_weekdays': [7], 'holiday_dates': ['2026-10-26'],
    'working_dates': ['2026-11-01'], 'include_japanese_holidays': false,
  });
  String propose(String start, String day, {CompanyWorkCategoryPolicy? using}) =>
    (using ?? policy).propose(clockInAt: DateTime.parse(start), workDate: DateTime.parse(day));
  test('JST night boundaries include start and exclude end', () {
    expect(propose('2026-10-27T12:59:59Z', '2026-10-27'), 'day');
    expect(propose('2026-10-27T13:00:00Z', '2026-10-27'), 'night');
    expect(propose('2026-10-27T19:59:59Z', '2026-10-27'), 'night');
    expect(propose('2026-10-27T20:00:00Z', '2026-10-27'), 'day');
    expect(propose('2026-10-27T22:00:00+09:00', '2026-10-27'), 'night');
  });
  test('holiday uses saved work date including overnight clock-in', () {
    expect(propose('2026-10-25T13:00:00Z', '2026-10-25'), 'holiday_night');
    expect(propose('2026-10-26T00:00:00Z', '2026-10-26'), 'holiday');
    expect(propose('2026-10-26T15:00:00Z', '2026-10-26'), 'holiday_night');
    expect(propose('2026-11-01T00:00:00Z', '2026-11-01'), 'day');
  });
  test('Japanese holiday is opt-in and explicit working day takes priority', () {
    expect(propose('2026-11-03T00:00:00Z', '2026-11-03'), 'day');
    final national = CompanyWorkCategoryPolicy.parse({...policy.toJson(), 'include_japanese_holidays': true});
    expect(propose('2026-11-03T00:00:00Z', '2026-11-03', using: national), 'holiday');
    final working = CompanyWorkCategoryPolicy.parse({...national.toJson(), 'working_dates': ['2026-11-03']});
    expect(propose('2026-11-03T13:00:00Z', '2026-11-03', using: working), 'night');
  });
  test('same-day window and roundtrip', () {
    final daytimeNight = CompanyWorkCategoryPolicy.parse({...policy.toJson(), 'night_start_minute': 600, 'night_end_minute': 960});
    expect(propose('2026-10-27T01:00:00Z', '2026-10-27', using: daytimeNight), 'night');
    expect(propose('2026-10-27T07:00:00Z', '2026-10-27', using: daytimeNight), 'day');
    expect(CompanyWorkCategoryPolicy.parse(policy.toJson()).toJson(), policy.toJson());
  });
  test('invalid and ambiguous settings fail closed', () {
    final invalid = [
      {...policy.toJson(), 'schema': 2},
      {...policy.toJson(), 'night_start_minute': 1440},
      {...policy.toJson(), 'night_end_minute': 1320},
      {...policy.toJson(), 'night_start_minute': 1320.0},
      {...policy.toJson(), 'holiday_weekdays': [0]},
      {...policy.toJson(), 'holiday_weekdays': [7, 7]},
      {...policy.toJson(), 'holiday_dates': ['2026-02-30']},
      {...policy.toJson(), 'holiday_dates': ['2026-01-1']},
      {...policy.toJson(), 'working_dates': ['2026-10-26']},
      {...policy.toJson(), 'include_japanese_holidays': 'false'},
      {...policy.toJson(), 'unexpected': true},
    ];
    for (final input in invalid) { expect(() => CompanyWorkCategoryPolicy.parse(input), throwsFormatException); }
  });
  test('unconfigured policy is not a default authority', () {
    final raw = {'schema': 1, 'actor_id': 'actor', 'company_id': 'company', 'revision': 0, 'can_manage': true, 'policy': null};
    expect(CompanyWorkCategorySnapshot.parse(raw, actorId: 'actor', companyId: 'company').policy, isNull);
    for (final changed in [
      {...raw, 'actor_id': 'other'}, {...raw, 'company_id': 'other'},
      {...raw, 'revision': 1}, {...raw, 'revision': 0, 'policy': policy.toJson()},
    ]) {
      expect(() => CompanyWorkCategorySnapshot.parse(changed, actorId: 'actor', companyId: 'company'), throwsFormatException);
    }
  });
}

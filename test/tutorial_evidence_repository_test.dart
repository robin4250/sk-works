import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';

class FixtureSource implements TutorialEvidenceSource, TutorialSetupEvidenceSource {
  int setupReads = 0;
  List<Map<String, dynamic>>? setup = [];
  @override
  Future<List<Map<String, dynamic>>?> setupRows(String actionKey, String companyId) async {
    setupReads++;
    if (unavailable) throw StateError('denied');
    return setup;
  }

  String role = 'admin';
  bool unavailable = false;
  int companyReads = 0;
  Map<String, dynamic>? profileRow = {
    'user_id': 'u1', 'display_name': '保存済み氏名', 'phone': '',
  };
  Map<String, dynamic>? personnelRow = {
    'worker_id': 'w1', 'name': '保存済み氏名', 'address': '',
    'blood_type': '', 'role': '', 'emergency_name': '',
    'emergency_relation': '', 'emergency_phone': '', 'emergency_address': '',
  };
  Map<String, dynamic>? docs;

  @override
  Future<Map<String, dynamic>?> membership() async =>
      {'company_id': 'c1', 'role': role};
  @override
  Future<Map<String, dynamic>?> profile() async {
    if (unavailable) throw StateError('network failure');
    return profileRow;
  }
  @override
  Future<Map<String, dynamic>?> personnel() async => personnelRow;
  @override
  Future<Map<String, dynamic>?> company() async {
    companyReads++;
    return {'name': '保存済み会社名', 'address': '', 'phone': '', 'email': ''};
  }
  @override
  Future<Map<String, dynamic>?> documents(String companyId) async => docs;
}

void main() {
  test('delegated manager only reads visible setup routes; viewer reads none', () async {
    final source = FixtureSource()..role = 'manager';
    final repo = TutorialEvidenceRepository(source);
    var result = await repo.load(availableActionKeys: {'payroll_settings'});
    expect(source.setupReads, 1);
    expect(result.tasks.single.actionKey, 'payroll_settings');
    expect(result.tasks.single.requiredForCompletion, isFalse);
    expect(result.tasks.single.checkpoints.single.state, TutorialEvidenceState.notApplicable);
    source.role = 'viewer';
    result = await repo.load(availableActionKeys: {'payroll_settings'});
    expect(result.tasks, isEmpty);
    expect(source.setupReads, 1);
  });

  test('saved settings count even zero rates; missing and denied remain distinct', () async {
    final source = FixtureSource()..setup = [
      {'id': 'w1', 'name': '一人目', 'configured': true, 'daily_rate_yen': 0},
      {'id': 'w2', 'name': '二人目', 'configured': false},
    ];
    final repo = TutorialEvidenceRepository(source);
    var result = await repo.load(availableActionKeys: {'payroll_settings'});
    expect(result.tasks.single.checkpoints.map((item) => item.state),
      [TutorialEvidenceState.saved, TutorialEvidenceState.missing]);
    source.unavailable = true;
    result = await repo.load(availableActionKeys: {'payroll_settings'});
    expect(result.tasks.single.checkpoints.single.state, TutorialEvidenceState.unknown);
  });

  test('optional registration absence never forces company to use subcontractors', () {
    final rows = TutorialEvidenceRepository.setupCheckpoints('subcontractors', [], label: '下請け');
    expect(rows.single.state, TutorialEvidenceState.missing);
    final settings = TutorialEvidenceRepository.setupCheckpoints('payment_certificate_settings', [], label: '設定');
    expect(settings.single.state, TutorialEvidenceState.notApplicable);
  });

  final today = DateTime(2026, 10, 8);
  final routes = {'profile', 'company_documents', 'document_register'};

  test('missing saved phone and unknown transport remain distinct', () async {
    final source = FixtureSource();
    final repo = TutorialEvidenceRepository(source, today: today);
    var snapshot = await repo.load(availableActionKeys: routes);
    var profile = snapshot.tasks.firstWhere((task) => task.key == 'personal_profile');
    expect(profile.checkpoints[0].state, TutorialEvidenceState.saved);
    expect(profile.checkpoints[0].evidenceKey, 'u1:display_name');
    expect(profile.checkpoints[1].state, TutorialEvidenceState.missing);
    source.unavailable = true;
    snapshot = await repo.load(availableActionKeys: routes);
    profile = snapshot.tasks.firstWhere((task) => task.key == 'personal_profile');
    expect(profile.checkpoints.every((item) => item.state == TutorialEvidenceState.unknown), isTrue);
  });

  test('viewer and manager never read company admin data even if route supplied', () async {
    for (final role in ['viewer', 'manager', 'employee']) {
      final source = FixtureSource()..role = role;
      final snapshot = await TutorialEvidenceRepository(source).load(availableActionKeys: routes);
      expect(source.companyReads, 0);
      expect(snapshot.tasks.any((task) => task.actionKey == 'company_documents'), isFalse);
    }
  });

  test('optional profile/company details do not become required checkpoints', () async {
    final snapshot = await TutorialEvidenceRepository(FixtureSource()).load(availableActionKeys: routes);
    final required = snapshot.tasks.where((task) => task.requiredForCompletion)
        .expand((task) => task.checkpoints).map((item) => item.key).toSet();
    expect(required, isNot(contains('blood_type')));
    expect(required, isNot(contains('address')));
    expect(required, isNot(contains('bank_account_number')));
    final recommended = snapshot.tasks.where((task) => !task.requiredForCompletion);
    expect(recommended.length, 2);
    expect(recommended.expand((task) => task.checkpoints)
        .every((item) => item.state == TutorialEvidenceState.missing), isTrue);
  });

  test('unavailable worker is unknown while verified absence of requirements is not applicable', () {
    expect(TutorialEvidenceRepository.documentCheckpoints(
      {'worker_id': null, 'requirements': [], 'statuses': []}, today: today,
    ).single.state, TutorialEvidenceState.unknown);
    expect(TutorialEvidenceRepository.documentCheckpoints(
      {'worker_id': 'w1', 'requirements': [], 'statuses': []}, today: today,
    ).single.state, TutorialEvidenceState.notApplicable);
  });

  test('document evidence uses own saved status and date boundary', () {
    Map<String, dynamic> docs(String expiry) => {
      'worker_id': 'w1',
      'requirements': [{'id': 'r1', 'name': '免許', 'is_active': true,
        'is_required': true, 'expiry_required': true}],
      'statuses': [{'id': 's1', 'worker_id': 'w1', 'requirement_id': 'r1',
        'status': 'submitted', 'expires_at': expiry}],
    };
    TutorialEvidenceState state(String expiry) =>
      TutorialEvidenceRepository.documentCheckpoints(docs(expiry), today: today).single.state;
    expect(state('2026-10-07'), TutorialEvidenceState.missing);
    expect(state('2026-10-08'), TutorialEvidenceState.saved);
    expect(state(''), TutorialEvidenceState.missing);
    expect(state('invalid'), TutorialEvidenceState.unknown);
    final otherWorker = docs('2026-10-09');
    (otherWorker['statuses'] as List).single['worker_id'] = 'w2';
    expect(TutorialEvidenceRepository.documentCheckpoints(otherWorker, today: today).single.state,
      TutorialEvidenceState.missing);
  });

  test('disabled routes yield no tasks and no company read', () async {
    final source = FixtureSource();
    final snapshot = await TutorialEvidenceRepository(source).load(availableActionKeys: {});
    expect(snapshot.tasks, isEmpty);
    expect(source.companyReads, 0);
  });
}

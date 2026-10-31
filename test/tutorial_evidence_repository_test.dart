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
  test('birth date is read from the existing personnel profile as optional evidence', () async {
    final source = FixtureSource();
    source.personnelRow = {...source.personnelRow!, 'birth_date': '1980-01-02'};
    final snapshot = await TutorialEvidenceRepository(source).load(availableActionKeys: {'profile'});
    final details = snapshot.tasks.singleWhere((task) => task.key == 'personnel_details_recommended');
    final birth = details.checkpoints.singleWhere((item) => item.key == 'birth_date');
    expect(details.requiredForCompletion, isFalse);
    expect(birth.label, '生年月日');
    expect(birth.state, TutorialEvidenceState.saved);
    expect(birth.evidenceKey, 'w1:birth_date');
    expect(source.personnelRow!['birth_date'], '1980-01-02');
  });

  test('multi-photo evidence uses the same retained-photo parser as document screens', () {
    TutorialEvidenceCheckpoint checkpoint(Object? paths, {String? legacy}) =>
      TutorialEvidenceRepository.documentCheckpoints({
        'worker_id': 'w1',
        'requirements': [{'id': 'r1', 'name': '雇用保険被保険者証', 'is_active': true, 'is_required': true}],
        'statuses': [{'id': 's1', 'worker_id': 'w1', 'requirement_id': 'r1',
          'status': 'submitted', 'attachment_paths': paths, 'attachment_path': legacy}],
      }, today: DateTime(2026, 10, 31)).single;
    expect(checkpoint(['synthetic/a', 'synthetic/b']).state, TutorialEvidenceState.saved);
    expect(checkpoint(['synthetic/a']).statusLabel, '提出済み');
    expect(checkpoint([], legacy: 'synthetic/legacy').state, TutorialEvidenceState.saved);
    expect(checkpoint([]).state, TutorialEvidenceState.missing);
    expect(checkpoint([]).statusLabel, '添付待ち');
    for (final invalid in ['invalid', [''], ['synthetic/a', 'synthetic/a'], [1]]) {
      expect(checkpoint(invalid, legacy: 'synthetic/legacy').state, TutorialEvidenceState.unknown);
      expect(checkpoint(invalid).statusLabel, '添付情報を確認');
    }
  });

  test('four membership roles only receive authorized preparation actions', () async {
    const personal = {'profile', 'document_register'};
    const setup = {'trade_companies', 'subcontractors', 'site_register',
      'payroll_settings', 'payment_certificate_settings'};
    for (final role in ['employee', 'viewer', 'manager', 'admin']) {
      final source = FixtureSource()..role = role;
      // Include read-only management routes for viewer: a visible page alone
      // must not turn company registration into a required viewer task.
      final allowed = {...personal, ...setup, 'company_documents'};
      final snapshot = await TutorialEvidenceRepository(source)
          .load(availableActionKeys: allowed);
      final actions = snapshot.tasks.map((task) => task.actionKey).toSet();
      expect(actions.difference(allowed), isEmpty);
      if (role == 'employee' || role == 'viewer') {
        expect(actions.intersection(setup), isEmpty);
        expect(source.setupReads, 0);
      }
      expect(actions.contains('company_documents'), role == 'admin');
      final disabled = await TutorialEvidenceRepository(source)
          .load(availableActionKeys: {'profile'});
      expect(disabled.tasks.every((task) => task.actionKey == 'profile'), isTrue);
    }
  });

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

  test('enabled settings for existing targets are required; zero rates are valid', () async {
    for (final action in ['payroll_settings', 'payment_certificate_settings']) {
      final source = FixtureSource()..setup = [
        {'id': 'target1', 'configured': false},
      ];
      final repo = TutorialEvidenceRepository(source);
      var task = (await repo.load(availableActionKeys: {action})).tasks.single;
      expect(task.requiredForCompletion, isTrue);
      expect(task.checkpoints.single.state, TutorialEvidenceState.missing);
      source.setup = [{'id': 'target1', 'configured': true, 'daily_rate_yen': 0}];
      task = (await repo.load(availableActionKeys: {action})).tasks.single;
      expect(task.requiredForCompletion, isTrue);
      expect(task.checkpoints.single.state, TutorialEvidenceState.saved);
      source.unavailable = true;
      task = (await repo.load(availableActionKeys: {action})).tasks.single;
      expect(task.requiredForCompletion, isTrue);
      expect(task.checkpoints.single.state, TutorialEvidenceState.unknown);
    }
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
        'status': 'submitted', 'expires_at': expiry, 'attachment_path': 'synthetic/path'}],
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

  test('required attachments match attention without assuming bank evidence', () {
    Map<String, dynamic> docs(String name, Map<String, dynamic> status) => {
      'worker_id': 'w1',
      'requirements': [{'id': 'r1', 'name': name, 'is_active': true,
        'is_required': true, 'expiry_required': false}],
      'statuses': [{'id': 's1', 'worker_id': 'w1', 'requirement_id': 'r1',
        'status': 'submitted', ...status}],
    };
    TutorialEvidenceState state(String name, Map<String, dynamic> status) =>
      TutorialEvidenceRepository.documentCheckpoints(docs(name, status), today: today).single.state;
    expect(state('免許', {'attachment_path': null}), TutorialEvidenceState.missing);
    expect(state('免許', {'attachment_path': ''}), TutorialEvidenceState.missing);
    expect(state('免許', {'attachment_path': 'synthetic/path'}), TutorialEvidenceState.saved);
    expect(state('免許', {}), TutorialEvidenceState.unknown);
    expect(state('銀行口座情報', {'attachment_path': null}), TutorialEvidenceState.unknown);
  });

  test('disabled routes yield no tasks and no company read', () async {
    final source = FixtureSource();
    final snapshot = await TutorialEvidenceRepository(source).load(availableActionKeys: {});
    expect(snapshot.tasks, isEmpty);
    expect(source.companyReads, 0);
  });
}

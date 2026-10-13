import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/tutorial/tutorial_progress.dart';

TutorialTask task(String id, {List<String>? checkpoints,
  TutorialRequirement requirement = TutorialRequirement.required,
  TutorialApplicability applicability = TutorialApplicability.applicable,
  Set<TutorialRole> roles = const {TutorialRole.administrator},
  TutorialPriority priority = TutorialPriority.normal, DateTime? dueAt,
}) => TutorialTask(id: id, title: id, roles: roles, requirement: requirement,
    checkpointIds: checkpoints ?? ['$id.saved'], applicability: applicability,
    priority: priority, dueAt: dueAt);

TutorialProgress progress(List<TutorialTask> tasks, Map<String, TutorialEvidence> evidence,
    {TutorialRole role = TutorialRole.administrator}) => TutorialProgress.evaluate(
    tasks: tasks, evidence: evidence, role: role, now: DateTime.utc(2026, 10, 8));

void main() {
  test('progress is the unweighted count of saved applicable checkpoints', () {
    final value = progress([task('company', checkpoints: ['name', 'phone', 'address'])], {
      'name': TutorialEvidence.saved('company:registered-name'),
      'phone': TutorialEvidence.saved('company:registered-phone'),
      'address': const TutorialEvidence.missing(),
    });
    expect(value.overall.completed, 2);
    expect(value.overall.total, 3);
    expect(value.overall.percentage, closeTo(200 / 3, 0.001));
    expect(value.overall.remaining, 1);
    expect(value.overall.state, TutorialProgressState.inProgress);
  });
  test('not-yet-loaded evidence is unknown and must not display zero percent', () {
    final value = progress([task('profile')], {});
    expect(value.overall.unknown, 1);
    expect(value.overall.state, TutorialProgressState.unknown);
    expect(value.overall.percentage, isNull);
    expect(value.overall.remaining, isNull);
  });
  test('partly loaded data does not claim an exact percent or remaining count', () {
    final value = progress([task('profile', checkpoints: ['saved', 'unloaded', 'missing'])], {
      'saved': TutorialEvidence.saved('profile:1'),
      'missing': const TutorialEvidence.missing(),
    });
    expect(value.overall.completed, 1);
    expect(value.overall.total, 3);
    expect(value.overall.knownRemaining, 1);
    expect(value.overall.percentage, isNull);
    expect(value.overall.remaining, isNull);
  });
  test('confirmed missing evidence can truthfully display zero percent', () {
    final value = progress([task('profile')], {'profile.saved': const TutorialEvidence.missing()});
    expect(value.overall.percentage, 0);
    expect(value.overall.remaining, 1);
    expect(value.overall.state, TutorialProgressState.pending);
  });
  test('optional and inapplicable tasks are excluded from numerator and denominator', () {
    final value = progress([task('required'),
      task('optional', requirement: TutorialRequirement.optional),
      task('irrelevant', applicability: TutorialApplicability.notApplicable)], {
      'required.saved': TutorialEvidence.saved('required:1'),
    });
    expect(value.overall.completed, 1);
    expect(value.overall.total, 1);
    expect(value.overall.percentage, 100);
    expect(value.excludedOptionalTasks, 1);
    expect(value.excludedNotApplicableTasks, 1);
  });
  test('individual inapplicable checkpoints are transparently excluded', () {
    final value = progress([task('documents', checkpoints: ['license', 'unused'])], {
      'license': TutorialEvidence.saved('license:1'),
      'unused': const TutorialEvidence.notApplicable(),
    });
    expect(value.overall.total, 1);
    expect(value.overall.completed, 1);
    expect(value.overall.excludedNotApplicableCheckpoints, 1);
    expect(value.overall.percentage, 100);
  });
  test('unknown applicability prevents a guessed denominator', () {
    final value = progress([task('known'),
      task('undecided', applicability: TutorialApplicability.unknown)], {
      'known.saved': TutorialEvidence.saved('known:1'),
    });
    expect(value.overall.total, 1);
    expect(value.overall.unknownApplicabilityTasks, 1);
    expect(value.overall.percentage, isNull);
    expect(value.overall.isComplete, isFalse);
  });
  test('required and recommended progress remain separate', () {
    final value = progress([task('required'),
      task('recommended', requirement: TutorialRequirement.recommended)], {
      'required.saved': TutorialEvidence.saved('required:1'),
      'recommended.saved': const TutorialEvidence.missing(),
    });
    expect(value.required.percentage, 100);
    expect(value.required.isComplete, isTrue);
    expect(value.recommended.percentage, 0);
    expect(value.overall.percentage, 50);
  });
  test('tasks for other roles cannot block or inflate progress', () {
    final value = progress([task('company'),
      task('profile', roles: {TutorialRole.employee, TutorialRole.subAdministrator})], {
      'profile.saved': TutorialEvidence.saved('profile:1'),
    }, role: TutorialRole.employee);
    expect(value.overall.percentage, 100);
    expect(value.tasks.single.task.id, 'profile');
    expect(value.excludedOtherRoleTasks, 1);
    expect(tutorialRoleFromMembership('owner'), TutorialRole.administrator);
    expect(tutorialRoleFromMembership('admin'), TutorialRole.administrator);
    expect(tutorialRoleFromMembership('manager'), TutorialRole.subAdministrator);
    expect(tutorialRoleFromMembership('viewer'), TutorialRole.employee);
  });
  test('repeated task IDs and repeated checkpoint IDs cannot inflate counts', () {
    final repeated = task('company', checkpoints: ['name', 'name']);
    final value = progress([repeated, repeated], {'name': TutorialEvidence.saved('company:1')});
    expect(value.tasks, hasLength(1));
    expect(value.overall.total, 1);
    expect(value.overall.completed, 1);
  });
  test('conflicting same-ID tasks fail instead of hiding unfinished evidence', () {
    expect(() => progress([task('company'), task('company', checkpoints: ['different'])], {}),
        throwsArgumentError);
  });
  test('one checkpoint cannot be counted as two different tasks', () {
    expect(() => progress([task('a', checkpoints: ['shared']), task('b', checkpoints: ['shared'])], {}),
        throwsArgumentError);
  });
  test('external waiting stays distinct from missing and from complete', () {
    final value = progress([task('enrollment')], {
      'enrollment.saved': const TutorialEvidence.externalWaiting('Apple review'),
    });
    expect(value.overall.externalWaiting, 1);
    expect(value.overall.missing, 0);
    expect(value.overall.remaining, 1);
    expect(value.overall.percentage, 0);
    expect(value.overall.state, TutorialProgressState.externalWaiting);
  });
  test('overdue and priority ordering never change completion percentage', () {
    final tasks = [task('normal'), task('urgent', priority: TutorialPriority.urgent),
      task('overdue', dueAt: DateTime.utc(2026, 10, 7)),
      task('done', priority: TutorialPriority.urgent, dueAt: DateTime.utc(2026, 10, 1))];
    final evidence = {for (final t in tasks) t.checkpointIds.single: const TutorialEvidence.missing()};
    evidence['done.saved'] = TutorialEvidence.saved('done:1');
    final value = progress(tasks, evidence);
    expect(value.tasks.map((t) => t.task.id), ['overdue', 'urgent', 'normal', 'done']);
    expect(value.overall.percentage, 25);
    expect(value.tasks.last.isOverdue(DateTime.utc(2026, 10, 8)), isFalse);
  });
  test('deadline equality is not overdue and due dates sort earlier first', () {
    final value = progress([task('later', dueAt: DateTime.utc(2026, 10, 10)),
      task('today', dueAt: DateTime.utc(2026, 10, 8))], {
      'later.saved': const TutorialEvidence.missing(), 'today.saved': const TutorialEvidence.missing(),
    });
    expect(value.tasks.first.task.id, 'today');
    expect(value.tasks.first.isOverdue(DateTime.utc(2026, 10, 8)), isFalse);
  });
  test('an empty applicable set does not claim zero or one hundred percent', () {
    final value = progress([], {});
    expect(value.overall.state, TutorialProgressState.empty);
    expect(value.overall.percentage, isNull);
    expect(value.overall.remaining, 0);
    expect(value.overall.isComplete, isFalse);
  });
  test('completed guides can be reopened or restarted without resetting saved evidence', () {
    final evidence = {'a.saved': TutorialEvidence.saved('record-a'),
      'b.saved': TutorialEvidence.saved('record-b')};
    final tasks = [task('a'), task('b')];
    final value = progress(tasks, evidence);
    final session = TutorialGuideSession(taskIds: value.tasks.map((t) => t.task.id));
    final reopened = session.open('b');
    expect(reopened.currentTaskId, 'b');
    expect(reopened.restart().currentTaskId, 'a');
    expect(evidence['b.saved']?.persistedEvidenceId, 'record-b');
    expect(progress(tasks, evidence).overall.percentage, 100);
  });
  test('navigation does not manufacture completion for an unsaved checkpoint', () {
    final tasks = [task('a')];
    TutorialGuideSession(taskIds: ['a']).restart().open('a');
    expect(progress(tasks, {'a.saved': const TutorialEvidence.missing()}).overall.percentage, 0);
  });
  test('invalid evidence and definitions are rejected', () {
    expect(() => TutorialEvidence.saved('  '), throwsArgumentError);
    expect(() => task('', checkpoints: ['x']), throwsArgumentError);
    expect(() => task('empty', checkpoints: []), throwsArgumentError);
    expect(() => task('empty-checkpoint', checkpoints: ['']), throwsArgumentError);
    expect(() => TutorialGuideSession(taskIds: ['a'], position: 1), throwsRangeError);
    expect(() => TutorialGuideSession(taskIds: ['a']).open('b'), throwsArgumentError);
  });
}

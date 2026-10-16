import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/tutorial/tutorial_progress.dart';

void main() {
  test('viewer is distinct from employee and retains no administrator-only tasks', () {
    expect(tutorialRoleFromMembership('viewer'), TutorialRole.viewer);
    expect(tutorialRoleFromMembership('employee'), TutorialRole.employee);
    expect(tutorialRoleFromMembership('manager'), TutorialRole.subAdministrator);
    expect(tutorialRoleFromMembership('admin'), TutorialRole.administrator);
    final result = TutorialProgress.evaluate(
      tasks: [TutorialTask(id: 'admin-only', title: '会社設定',
        roles: [TutorialRole.administrator], requirement: TutorialRequirement.required,
        checkpointIds: ['company'])],
      role: TutorialRole.viewer, evidence: {}, now: DateTime(2026, 10, 16));
    expect(result.tasks, isEmpty);
    expect(result.excludedOtherRoleTasks, 1);
  });
}

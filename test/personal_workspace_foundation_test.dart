import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/employment_disconnect_transition.dart';
import 'package:sk_works/domain/personal_workspace.dart';
import 'package:sk_works/domain/personal_workspace_actions.dart';

void main() {
  test('personal workspace is permanent beneath company workspaces', () {
    expect(PersonalWorkspacePolicy.personalWorkspaceAlwaysExists(), isTrue);
    expect(
      PersonalWorkspacePolicy.deletePersonalWorkspaceOnEmploymentEnd(),
      isFalse,
    );
    expect(PersonalWorkspacePolicy.supportsMultipleCompanyWorkspaces(), isTrue);
  });

  test('last employment disconnect returns user to personal mode', () {
    expect(
      EmploymentDisconnectTransition.destination(
        remainingActiveCompanyMemberships: 0,
      ),
      EmploymentDisconnectDestination.personalWorkspace,
    );
    expect(
      EmploymentDisconnectTransition.personalModeMessage,
      contains('わたしの仕事データ'),
    );
  });

  test('personal mode exposes future connection and company creation routes', () {
    expect(
      PersonalWorkspaceActions.labels.values,
      contains('新しい勤務先と接続'),
    );
    expect(
      PersonalWorkspaceActions.labels.values,
      contains('会社を作ってSKOを始める'),
    );
  });
}

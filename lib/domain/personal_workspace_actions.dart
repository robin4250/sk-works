enum PersonalWorkspaceAction {
  viewWorkData,
  connectNewEmployer,
  createCompanyWorkspace,
}

class PersonalWorkspaceActions {
  const PersonalWorkspaceActions._();

  static const labels = <PersonalWorkspaceAction, String>{
    PersonalWorkspaceAction.viewWorkData: 'わたしの仕事データ',
    PersonalWorkspaceAction.connectNewEmployer: '新しい勤務先と接続',
    PersonalWorkspaceAction.createCompanyWorkspace: '会社を作ってSKOを始める',
  };
}

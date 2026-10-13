enum ConfirmedAction {
  register,
  edit,
  disable,
  approve,
  reject,
  permissionChange,
  companyDataSend,
}

class ConfirmationPolicy {
  const ConfirmationPolicy._();

  static bool requiresConfirmation(ConfirmedAction action) => true;

  static bool isReadOnlyAction(String actionKey) =>
      actionKey == 'view' ||
      actionKey == 'search' ||
      actionKey == 'filter' ||
      actionKey == 'navigate';
}

/// A fresh local master challenge precedes the server-authorized snapshot read.
/// This guard does not create a server-side proof of biometric verification.
Future<void> authorizeSecurityExport({
  required String? actor,
  required String? Function() currentActor,
  required bool Function() isActive,
  required Future<bool> Function() reauthenticate,
  required Future<void> Function() authorizeSnapshot,
}) async {
  void checkActor() {
    if (!isActive() || actor == null || currentActor() != actor) {
      throw StateError('Security export unavailable');
    }
  }

  checkActor();
  if (!await reauthenticate()) {
    throw StateError('Security export unavailable');
  }
  checkActor();
  await authorizeSnapshot();
  checkActor();
}

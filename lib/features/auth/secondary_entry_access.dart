import 'package:flutter/foundation.dart';

/// Optional server authorization for one protected page lifetime.
/// It must never retain the password or use a local biometric boolean as a
/// server-side authorization credential.
abstract class SecondaryEntryAccess extends ChangeNotifier {
  bool get requiredByServer;
  bool get isOpen;
  Future<void> prepare();
  Future<bool> unlock(String password);
  void invalidate();
  Future<void> close();
}

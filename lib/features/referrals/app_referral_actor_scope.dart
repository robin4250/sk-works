import 'dart:async';
import 'app_referral_repository.dart';

/// A page-scoped identity boundary, permanently invalid after A -> B -> A.
/// This does not grant permissions or cancel requests already sent to a server.
class AppReferralActorScope {
  AppReferralActorScope(this.repository, {required this.onInvalidated})
      : actor = repository.currentActorId {
    _subscription = repository.watchActorChanges().listen((next) {
      if (next != actor) invalidate();
    }, onError: (Object _) => invalidate());
  }
  final AppReferralRepository repository;
  final String? actor;
  final void Function() onInvalidated;
  StreamSubscription<String?>? _subscription;
  bool _invalidated = false;
  bool _disposed = false;
  bool get valid => !_disposed && !_invalidated && actor != null &&
      repository.currentActorId == actor;
  bool check() {
    if (!valid) invalidate();
    return valid;
  }
  void invalidate() {
    if (_disposed || _invalidated) return;
    _invalidated = true;
    onInvalidated();
  }
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
  }
}

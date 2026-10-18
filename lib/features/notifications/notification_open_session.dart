import 'dart:async';

/// A notification snapshot belongs to the account that started loading it.
class NotificationOpenSession {
  NotificationOpenSession({
    required String? Function() actor,
    required Stream<String?> changes,
  }) : _actor = actor,
       _initialActor = actor() {
    _subscription = changes.listen(
      (next) {
        if (next != _initialActor) _invalidate();
      },
      onError: (Object _) => _invalidate(),
      onDone: _invalidate,
    );
  }
  final String? Function() _actor;
  final String? _initialActor;
  late final StreamSubscription<String?> _subscription;
  final _events = StreamController<void>.broadcast(sync: true);
  bool _invalid = false;
  Stream<void> get invalidations => _events.stream;
  bool get isCurrent =>
      !_invalid && _initialActor != null && _actor() == _initialActor;
  void requireCurrent() {
    if (!isCurrent) throw StateError('通知一覧を開き直してください。');
  }

  void invalidate() => _invalidate();

  void _invalidate() {
    if (_invalid) return;
    _invalid = true;
    _events.add(null);
  }

  Future<void> dispose() async {
    _invalidate();
    await _subscription.cancel();
    await _events.close();
  }
}

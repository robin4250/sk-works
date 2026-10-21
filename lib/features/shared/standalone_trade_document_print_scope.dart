import 'dart:typed_data';

enum StandalonePrintVisibility { resumed, inactive, hidden, paused, detached }

/// A native print dialog may make the app inactive while requesting its PDF.
/// Only that explicit lease may retain the exact bytes under the same scope.
class StandaloneTradeDocumentPrintScope {
  StandaloneTradeDocumentPrintScope({
    required void Function() verifyScope,
    required Uint8List? Function() currentBytes,
    required Object Function() currentTarget,
    required void Function() onRevoke,
  }) : _verifyScope = verifyScope,
       _currentBytes = currentBytes,
       _currentTarget = currentTarget,
       _onRevoke = onRevoke;

  final void Function() _verifyScope, _onRevoke;
  final Uint8List? Function() _currentBytes;
  final Object Function() _currentTarget;
  StandalonePrintVisibility _visibility = StandalonePrintVisibility.resumed;
  Uint8List? _bytes;
  Object? _target;
  bool _printing = false, _revoked = false;

  void invalidate() {
    if (_revoked) {
      return;
    }
    _revoked = true;
    _printing = false;
    _bytes = null;
    _target = null;
    _onRevoke();
  }

  Never _refuse() {
    invalidate();
    throw StateError('印刷状態が変わりました。会社詳細から開き直してください。');
  }

  void _check() {
    if (_revoked) {
      _refuse();
    }
    try {
      _verifyScope();
    } catch (_) {
      invalidate();
      rethrow;
    }
  }

  void begin(Uint8List bytes) {
    _check();
    if (_printing || _visibility != StandalonePrintVisibility.resumed ||
        !identical(bytes, _currentBytes())) {
      _refuse();
    }
    _bytes = bytes;
    _target = _currentTarget();
    _printing = true;
  }

  Uint8List layout() {
    _check();
    if (!_printing || _target != _currentTarget() ||
        !identical(_bytes, _currentBytes()) ||
        !const {StandalonePrintVisibility.resumed, StandalonePrintVisibility.inactive}
            .contains(_visibility)) {
      _refuse();
    }
    return _bytes!;
  }

  void visibilityChanged(StandalonePrintVisibility state) {
    _visibility = state;
    if (_revoked) {
      return;
    }
    if (state == StandalonePrintVisibility.resumed) {
      return;
    }
    if (state == StandalonePrintVisibility.inactive && _printing) {
      layout(); // Revalidate scope/target/identity on entry to the native dialog.
      return;
    }
    invalidate();
  }

  void end() {
    _printing = false;
    _bytes = null;
    _target = null;
    if (_visibility != StandalonePrintVisibility.resumed) {
      invalidate();
    }
  }
}

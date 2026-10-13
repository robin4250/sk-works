import 'dart:async';
import 'dart:typed_data';

/// Reuses one PDF generation for preview, print and share until data changes.
/// Failed generations are evicted so the next request can retry.
class PdfBytesCache {
  Future<Uint8List>? _pending;

  Future<Uint8List> get(FutureOr<Uint8List> Function() build) {
    final existing = _pending;
    if (existing != null) {
      return existing;
    }
    late final Future<Uint8List> generation;
    generation = Future<Uint8List>.sync(build).then(
      (bytes) => bytes,
      onError: (Object error, StackTrace stack) {
        if (identical(_pending, generation)) {
          _pending = null;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _pending = generation;
    return generation;
  }

  void invalidate() => _pending = null;
}

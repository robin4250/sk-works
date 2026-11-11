/// Review-only client building block. A server implementation and integration
/// at every output entry point are prerequisites; this does not protect old
/// clients or PDF bytes already handed off to the operating system.
class InvoiceOutputIdentity {
  const InvoiceOutputIdentity({required this.invoiceId, required this.revision});
  final String invoiceId;
  final String revision;
}

class InvoiceOutputPermit {
  const InvoiceOutputPermit({required this.invoiceId, required this.revision, required this.allowed});
  final String invoiceId;
  final String revision;
  final bool allowed;
}

class InvoiceOutputDenied implements Exception {
  const InvoiceOutputDenied();
}

/// Each callback must perform a fresh, authenticated online server check.
/// An offline cache or a prior successful result cannot serve as a check.
typedef InvoicePermitCheck = Future<List<InvoiceOutputPermit>> Function(List<InvoiceOutputIdentity> identities);

class InvoiceOutputGuard {
  const InvoiceOutputGuard(this.check);
  final InvoicePermitCheck check;

  Future<void> _verify(List<InvoiceOutputIdentity> inputs) async {
    if (inputs.isEmpty || inputs.any((i) => i.invoiceId.isEmpty || i.revision.isEmpty) ||
        inputs.map((i) => i.invoiceId).toSet().length != inputs.length) {
      throw const InvoiceOutputDenied();
    }
    final permits = await check(List.unmodifiable(inputs));
    if (permits.length != inputs.length) throw const InvoiceOutputDenied();
    final byId = <String, InvoiceOutputPermit>{};
    for (final permit in permits) {
      if (byId.containsKey(permit.invoiceId)) throw const InvoiceOutputDenied();
      byId[permit.invoiceId] = permit;
    }
    for (final input in inputs) {
      final permit = byId[input.invoiceId];
      if (permit == null || !permit.allowed || permit.revision != input.revision) {
        throw const InvoiceOutputDenied();
      }
    }
  }

  /// Check before creating bytes and again before handing bytes to the OS.
  /// Server revalidation closes stale-cache reuse but cannot revoke a PDF
  /// already handed off or eliminate the check-to-handoff race by itself.
  Future<void> run<T>(List<InvoiceOutputIdentity> identities,
      Future<T> Function() build, Future<void> Function(T bytes) handoff) async {
    final stable = List<InvoiceOutputIdentity>.unmodifiable(identities);
    await _verify(stable);
    final bytes = await build();
    await _verify(stable);
    await handoff(bytes);
  }
}

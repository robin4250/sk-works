import 'package:flutter/foundation.dart';

/// Optional operation boundary supplied by the new managed-document hub.
/// Legacy callers do not acquire a new permission by omitting this gate. The
/// hub must provide a captured actor/session/company/revision implementation,
/// fail closed when the server capability is absent, and notify on revocation.
abstract interface class StandaloneTradeDocumentOperationGate implements Listenable {
  String get companyId;
  String get tradeCompanyId;
  bool get acceptance;
  void requireCurrent();
  Future<void> refresh();
}

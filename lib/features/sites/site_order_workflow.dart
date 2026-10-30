import 'dart:convert';

/// Financial order records never become fields of the ordinary site directory.
/// These DTOs are for the protected management workspace, not SiteRecord.
class SiteOrderScope {
  const SiteOrderScope({required this.actorId, required this.companyId,
    required this.sessionId, required this.siteId});
  final String actorId, companyId, sessionId, siteId;
  bool get valid => [actorId, companyId, sessionId, siteId]
    .every((value) => value.trim().isNotEmpty);

  bool sameAs(SiteOrderScope other) => actorId == other.actorId &&
    companyId == other.companyId && sessionId == other.sessionId &&
    siteId == other.siteId;
}

class SiteOrderPrice {
  SiteOrderPrice({required this.item, required this.unitPriceYen,
    required this.unit}) {
    if (item.trim().isEmpty || unit.trim().isEmpty || unitPriceYen < 0 ||
        unitPriceYen > 9007199254740991) {
      throw FormatException('注文書の単価・単位を確認できません。');
    }
  }
  final String item, unit;
  final int unitPriceYen;
  Map<String, Object> toJson() => {'item': item,
    'unit_price_yen': unitPriceYen, 'unit': unit};
}

enum SiteOrderArtifactKind { order, acceptance }

/// A *server-issued* immutable artifact. Construction is not authorization:
/// adapters must verify this record on the server again before every operation.
class SiteOrderArtifact {
  SiteOrderArtifact({required this.id, required this.companyId,
    required this.siteId, required this.revision, required this.pdfSha256,
    required this.title, required this.startsOn, required this.endsOn,
    required this.sealVersionId, required this.kind, required List<SiteOrderPrice> prices})
    : prices = List.unmodifiable(prices) {
    if ([id, companyId, siteId, sealVersionId, title].any((s) => s.trim().isEmpty) ||
        revision < 1 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(pdfSha256) ||
        !_date(startsOn) || !_date(endsOn) ||
        endsOn.compareTo(startsOn) < 0 || prices.isEmpty) {
      throw FormatException('保存された押印注文書を確認できません。');
    }
  }
  final String id, companyId, siteId, pdfSha256, title, startsOn, endsOn,
    sealVersionId;
  final int revision;
  final SiteOrderArtifactKind kind;
  final List<SiteOrderPrice> prices;
  String get period => '$startsOn ～ $endsOn';
  String get fingerprint => jsonEncode({'id': id, 'company_id': companyId,
    'site_id': siteId, 'revision': revision, 'pdf_sha256': pdfSha256, 'kind': kind.name,
    'seal_version_id': sealVersionId, 'title': title,
    'starts_on': startsOn, 'ends_on': endsOn,
    'prices': prices.map((p) => p.toJson()).toList()});

  static bool _date(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
    final date = DateTime.tryParse(value);
    return date != null && date.toIso8601String().startsWith(value);
  }
}

class SiteOrderRecipient {
  const SiteOrderRecipient({required this.tradeCompanyId,
    required this.companyId, required this.name, required this.connectionVersion});
  final String tradeCompanyId, companyId, name;
  final int connectionVersion;
  String get fingerprint => jsonEncode([tradeCompanyId, companyId, name,
    connectionVersion]);
}

class SiteOrderDeliveryIntent {
  const SiteOrderDeliveryIntent({required this.requestId, required this.scope,
    required this.artifact, required this.recipient});
  final String requestId;
  final SiteOrderScope scope;
  final SiteOrderArtifact artifact;
  final SiteOrderRecipient recipient;
}

class SiteOrderDeliveryReceipt {
  const SiteOrderDeliveryReceipt({required this.requestId,
    required this.companyId, required this.siteId, required this.artifactId,
    required this.artifactRevision, required this.pdfSha256,
    required this.recipientCompanyId, required this.deliveryId,
    required this.actorId, required this.sessionId,
    required this.recipientConnectionVersion});
  final String requestId, companyId, siteId, artifactId, pdfSha256,
    recipientCompanyId, deliveryId;
  final String actorId, sessionId;
  final int artifactRevision, recipientConnectionVersion;
  bool matches(SiteOrderDeliveryIntent intent) =>
    requestId == intent.requestId && companyId == intent.scope.companyId &&
    siteId == intent.scope.siteId && artifactId == intent.artifact.id &&
    artifactRevision == intent.artifact.revision &&
    pdfSha256 == intent.artifact.pdfSha256 &&
    recipientCompanyId == intent.recipient.companyId && deliveryId.isNotEmpty &&
    actorId == intent.scope.actorId && sessionId == intent.scope.sessionId &&
    recipientConnectionVersion == intent.recipient.connectionVersion;
}

enum SiteOrderSendState { selecting, confirming, preparing, sending, outcomeUnknown, sent, retired }

/// Two deliberate confirmations bound to one immutable artifact and recipient.
/// A timeout retains the same intent/request id for receipt lookup. It does not
/// permit a new send, changing the recipient or guessing that the TX failed.
class SiteOrderSendWorkflow {
  SiteOrderSendWorkflow({required this.scope, required this.artifact,
    required this.currentScope, required this.isArtifactCurrent,
    required this.isRecipientCurrent, required this.newRequestId,
    required this.persistIntent}) {
    if (!scope.valid || artifact.kind != SiteOrderArtifactKind.order ||
        artifact.companyId != scope.companyId || artifact.siteId != scope.siteId) {
      throw StateError('注文書の会社・現場が一致しません。');
    }
    _verify();
  }
  final SiteOrderScope scope;
  final SiteOrderArtifact artifact;
  final SiteOrderScope Function() currentScope;
  final bool Function(SiteOrderArtifact) isArtifactCurrent;
  final bool Function(SiteOrderRecipient) isRecipientCurrent;
  final String Function() newRequestId;
  /// Must finish durable, actor-scoped recovery storage *before* the network
  /// mutation starts. An in-memory callback is not a production adapter.
  final Future<void> Function(SiteOrderDeliveryIntent) persistIntent;
  SiteOrderSendState _state = SiteOrderSendState.selecting;
  SiteOrderSendState get state => _state;
  SiteOrderRecipient? _recipient;
  SiteOrderDeliveryIntent? _intent;
  SiteOrderDeliveryReceipt? _receipt;
  SiteOrderDeliveryReceipt? get receipt => _receipt;
  SiteOrderDeliveryIntent? get pendingIntent => _intent;

  void verify() => _verify();
  void retire() { _state = SiteOrderSendState.retired; }

  void _verify() {
    if (state == SiteOrderSendState.retired) throw StateError('開き直してください。');
    bool valid;
    try { valid = scope.sameAs(currentScope()) && isArtifactCurrent(artifact); }
    catch (_) { valid = false; }
    if (!valid) {
      _state = SiteOrderSendState.retired;
      throw StateError('ログイン・会社・注文書の状態が変わりました。開き直してください。');
    }
  }

  void select(SiteOrderRecipient recipient) {
    _verify();
    if (state != SiteOrderSendState.selecting ||
        recipient.companyId.isEmpty || recipient.companyId == scope.companyId ||
        recipient.tradeCompanyId.isEmpty || recipient.name.trim().isEmpty ||
        recipient.connectionVersion < 1 || !isRecipientCurrent(recipient)) {
      throw StateError('送信先の協力会社を確認してください。');
    }
    _recipient = recipient;
  }

  SiteOrderDeliveryIntent confirm() {
    _verify();
    final recipient = _recipient;
    if (state != SiteOrderSendState.selecting || recipient == null ||
        !isRecipientCurrent(recipient)) {
      throw StateError('送信先を選び直してください。');
    }
    final id = newRequestId();
    if (id.trim().isEmpty) throw StateError('送信操作を準備できません。');
    final intent = SiteOrderDeliveryIntent(requestId: id, scope: scope,
      artifact: artifact, recipient: recipient);
    _intent = intent;
    _state = SiteOrderSendState.confirming;
    return intent;
  }

  void returnToEditor() {
    _verify();
    if (!const [SiteOrderSendState.selecting, SiteOrderSendState.confirming]
        .contains(state)) {
      throw StateError('送信結果を確認してから戻ってください。');
    }
    _state = SiteOrderSendState.retired;
  }

  Future<void> send(Future<SiteOrderDeliveryReceipt> Function(
      SiteOrderDeliveryIntent) operation) async {
    _verify();
    final intent = _intent;
    if (state != SiteOrderSendState.confirming || intent == null ||
        !isRecipientCurrent(intent.recipient)) {
      throw StateError('送信先・注文書を確認し直してください。');
    }
    _state = SiteOrderSendState.preparing;
    try {
      await persistIntent(intent);
      _verify();
      if (!isRecipientCurrent(intent.recipient)) throw StateError('送信先を選び直してください。');
    } catch (_) {
      if (state != SiteOrderSendState.retired) {
        _state = SiteOrderSendState.selecting;
        _intent = null; // No network mutation has started; confirm afresh.
      }
      rethrow;
    }
    _state = SiteOrderSendState.sending;
    try {
      final result = await operation(intent);
      _verify();
      if (!isRecipientCurrent(intent.recipient) || !result.matches(intent)) {
        throw StateError('共有送信の保存結果を確認できません。');
      }
      _receipt = result;
      _state = SiteOrderSendState.sent;
    } catch (_) {
      if (state != SiteOrderSendState.retired) _state = SiteOrderSendState.outcomeUnknown;
      rethrow;
    }
  }

  Future<void> resolve(Future<SiteOrderDeliveryReceipt?> Function(
      SiteOrderDeliveryIntent) lookup) async {
    _verify();
    final intent = _intent;
    if (state != SiteOrderSendState.outcomeUnknown || intent == null) {
      throw StateError('照合対象の送信はありません。');
    }
    final result = await lookup(intent);
    _verify();
    // Absence alone cannot prove an in-flight transaction will not commit.
    if (result == null) return;
    if (!isRecipientCurrent(intent.recipient) || !result.matches(intent)) {
      throw StateError('共有送信の保存結果が一致しません。');
    }
    _receipt = result;
    _state = SiteOrderSendState.sent;
  }
}

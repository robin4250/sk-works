import 'site_order_workflow.dart';

/// Client-side shape validation only. The server must derive every identity,
/// permission, signature and contract binding from its canonical package.
class SiteOrderApprovalIntent {
  SiteOrderApprovalIntent({required this.requestId, required this.scope,
    required this.packageId, required this.packageRevision,
    required this.incomingOrder, required this.acceptance,
    required this.acceptedOrderPdfSha256}) {
    if (!scope.valid || requestId.trim().isEmpty || packageId.trim().isEmpty ||
        packageRevision < 1 || incomingOrder.kind != SiteOrderArtifactKind.order ||
        acceptance.kind != SiteOrderArtifactKind.acceptance ||
        incomingOrder.companyId == scope.companyId ||
        incomingOrder.counterpartyCompanyId != scope.companyId ||
        acceptance.companyId != scope.companyId ||
        acceptance.counterpartyCompanyId != incomingOrder.companyId ||
        acceptance.siteId != scope.siteId ||
        acceptedOrderPdfSha256 != incomingOrder.pdfSha256 ||
        !_samePrices(incomingOrder.prices, acceptance.prices)) {
      throw StateError('受信注文書と返送請書の内容・会社・保存版を確認してください。');
    }
  }
  final String requestId, packageId, acceptedOrderPdfSha256;
  final SiteOrderScope scope;
  final int packageRevision;
  final SiteOrderArtifact incomingOrder, acceptance;
  // Approval never takes an arbitrary recipient from a dropdown.
  String get acceptanceRecipientCompanyId => incomingOrder.companyId;
  static bool _samePrices(List<SiteOrderPrice> a, List<SiteOrderPrice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].item != b[i].item || a[i].unit != b[i].unit ||
          a[i].unitPriceYen != b[i].unitPriceYen) { return false; }
    }
    return true;
  }
}

/// Atomic approval receipt means acceptance *queued*, not transport completed.
class SiteOrderApprovalReceipt {
  const SiteOrderApprovalReceipt({required this.requestId, required this.actorId,
    required this.sessionId, required this.companyId, required this.packageId,
    required this.packageRevision, required this.incomingOrderPdfSha256,
    required this.acceptedSiteId, required this.acceptanceArtifactId,
    required this.acceptanceArtifactRevision, required this.acceptancePdfSha256,
    required this.acceptanceRecipientCompanyId, required this.acceptanceOutboxId});
  final String requestId, actorId, sessionId, companyId, packageId,
    incomingOrderPdfSha256, acceptedSiteId, acceptanceArtifactId,
    acceptancePdfSha256, acceptanceRecipientCompanyId, acceptanceOutboxId;
  final int packageRevision, acceptanceArtifactRevision;
  bool matches(SiteOrderApprovalIntent i) => requestId == i.requestId &&
    actorId == i.scope.actorId && sessionId == i.scope.sessionId &&
    companyId == i.scope.companyId && packageId == i.packageId &&
    packageRevision == i.packageRevision &&
    incomingOrderPdfSha256 == i.incomingOrder.pdfSha256 &&
    acceptedSiteId == i.scope.siteId && acceptanceArtifactId == i.acceptance.id &&
    acceptanceArtifactRevision == i.acceptance.revision &&
    acceptancePdfSha256 == i.acceptance.pdfSha256 &&
    acceptanceRecipientCompanyId == i.acceptanceRecipientCompanyId &&
    acceptanceOutboxId.trim().isNotEmpty;
}

enum SiteOrderNoticeKind { orderReceived, approvalRequired, orderAccepted,
  orderRejected, acceptanceReceived, acceptanceDeliveryPending }

/// Deep links contain only a notification UUID. The protected server lookup
/// resolves package/company/version; neither a title nor a supplied site ID
/// grants permission. Do not encode unit prices or storage URLs in a notice.
class SiteOrderNoticeTarget {
  SiteOrderNoticeTarget({required this.notificationId, required this.eventId,
    required this.companyId, required this.packageId, required this.packageRevision,
    required this.kind, required String expectedCompanyId}) {
    if (![notificationId, eventId, companyId, packageId].every(_uuid) ||
        companyId != expectedCompanyId || packageRevision < 1) {
      throw FormatException('通知の会社・注文書の対象を確認できません。');
    }
  }
  final String notificationId, eventId, companyId, packageId;
  final int packageRevision;
  final SiteOrderNoticeKind kind;
  static bool _uuid(String value) => RegExp(
    r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(value);

  static SiteOrderNoticeTarget fromJson(Object? value, {required String expectedCompanyId}) {
    if (value is! Map || value.length != 7 ||
        !const {'notification_id','event_id','company_id','package_id',
          'package_revision','kind','contract_version'}.every(value.containsKey) ||
        value['contract_version'] is! int || value['contract_version'] != 1 ||
        value['package_revision'] is! int) {
      throw FormatException('通知の保存結果を確認できません。');
    }
    final rawKind = value['kind'];
    final kinds = <String,SiteOrderNoticeKind>{
      'order_received': SiteOrderNoticeKind.orderReceived,
      'approval_required': SiteOrderNoticeKind.approvalRequired,
      'order_accepted': SiteOrderNoticeKind.orderAccepted,
      'order_rejected': SiteOrderNoticeKind.orderRejected,
      'acceptance_received': SiteOrderNoticeKind.acceptanceReceived,
      'acceptance_delivery_pending': SiteOrderNoticeKind.acceptanceDeliveryPending,
    };
    if (!kinds.containsKey(rawKind) ||
        !['notification_id','event_id','company_id','package_id']
          .every((key) => value[key] is String)) {
      throw FormatException('注文書通知の種類を確認できません。');
    }
    return SiteOrderNoticeTarget(notificationId:value['notification_id'] as String,
      eventId:value['event_id'] as String,companyId:value['company_id'] as String,
      packageId:value['package_id'] as String,packageRevision:value['package_revision'] as int,
      kind:kinds[rawKind]!,expectedCompanyId:expectedCompanyId);
  }
}

/// OFF, unknown and partially installed deployments all stop new operations.
/// Existing archive viewing is intentionally independent from the master switch.
/// This DTO cannot change the platform flag; only the existing master proof API
/// may do that after a separately reviewed, guarded server-key extension.
class SiteOrderAvailability {
  const SiteOrderAvailability({required this.canViewArchive, required this.canMutate});
  final bool canViewArchive, canMutate;
  static const featureKey = 'site_order_documents';
  factory SiteOrderAvailability.fromJson(Object? raw) {
    if (raw is! Map) return const SiteOrderAvailability(canViewArchive:false,canMutate:false);
    final archive = raw['site_order_archive_contract_version'] == 1 &&
      raw['site_order_archive_contract_version'] is int && raw['can_view_archive'] == true;
    final complete = const ['site_order_documents_contract_version',
      'site_order_artifact_contract_version','site_order_approval_contract_version',
      'site_order_delivery_contract_version','site_order_recovery_contract_version',
      'site_order_notification_contract_version'].every((key) => raw[key] is int && raw[key] == 1);
    return SiteOrderAvailability(canViewArchive:archive,
      canMutate:archive && complete && raw[featureKey] == true && raw['can_manage_orders'] == true);
  }
}

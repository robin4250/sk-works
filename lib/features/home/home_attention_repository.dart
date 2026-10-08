import '../notifications/attention_center_repository.dart';

class RequiredDocumentAttention {
  const RequiredDocumentAttention({
    required this.missingCount,
    required this.missingNames,
    required this.needsLicense,
    required this.needsQualification,
    this.paidLeaveApprovalCount = 0,
    this.generationIssueCount = 0,
    this.generationIssueMessages = const [],
    this.unresolvedCountOverride,
  });

  final int missingCount;
  final List<String> missingNames;
  final bool needsLicense;
  final bool needsQualification;
  final int paidLeaveApprovalCount;
  final int generationIssueCount;
  final List<String> generationIssueMessages;

  final int? unresolvedCountOverride;

  int get unresolvedCount => unresolvedCountOverride ??
      (missingCount + paidLeaveApprovalCount + generationIssueCount);
  bool get hasMissing => unresolvedCount > 0;
}

class HomeAttentionRepository {
  HomeAttentionRepository._(this._repository);

  final AttentionCenterRepository _repository;

  static HomeAttentionRepository? maybeCreate() {
    final repository = AttentionCenterRepository.maybeCreate();
    return repository == null ? null : HomeAttentionRepository._(repository);
  }

  Future<RequiredDocumentAttention> loadRequiredDocumentAttention() async {
    final data = await _repository.load();
    final pending = data.snapshot.items.where((item) => item.needsAction);
    final documents = pending.where((item) => item.source == 'required_document');
    final generation = pending.where((item) => item.source == 'generation_setting');
    return RequiredDocumentAttention(
      missingCount: documents.length,
      missingNames: documents.map((item) => item.title).toList(),
      needsLicense: false,
      needsQualification: false,
      paidLeaveApprovalCount: pending.where((item) => item.source == 'paid_leave').length,
      generationIssueCount: generation.length,
      generationIssueMessages: generation.map((item) => item.body).toList(),
      unresolvedCountOverride: data.snapshot.unresolvedCount,
    );
  }
}

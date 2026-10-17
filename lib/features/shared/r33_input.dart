/// Optional initial text from the exact preview the user opened.
/// This is not authorization; workspace permissions and save validation still apply.
class R33Input {
  const R33Input({required this.actorId, required this.companyId,
    required this.subjectId, required this.sourceRevision, required this.text});
  final String actorId, companyId, subjectId, sourceRevision, text;

  Map<String, dynamic> apply({required Map<String, dynamic> payload,
    required Map<String, dynamic> workspace, required String? actor,
    required String subjectKind, required String subject,
    required String revision}) {
    final result = Map<String, dynamic>.from(payload);
    if (workspace['attachment'] != null || subjectKind != 'invoice' ||
        actor == null || actor.isEmpty || actor != actorId ||
        companyId.isEmpty || workspace['company_id'] != companyId ||
        subjectId != subject || sourceRevision != revision ||
        text.trim().isEmpty || text.length > 240) {
      return result;
    }
    final serverRevision = DateTime.tryParse(workspace['source_revision']?.toString() ?? '');
    final previewRevision = DateTime.tryParse(sourceRevision);
    if (serverRevision == null || previewRevision == null ||
        !serverRevision.isAtSameMomentAs(previewRevision)) {
      return result;
    }
    final current = result['work_name'];
    if (current == null || (current is String && current.trim().isEmpty)) {
      result['work_name'] = text;
    }
    return result;
  }
}

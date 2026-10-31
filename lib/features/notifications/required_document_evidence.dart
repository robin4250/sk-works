/// States reported by the scoped evidence receipt. Saved is evidence, not a
/// submission status; exemptions remain separate from required documents.
enum RequiredDocumentEvidenceState { saved, missing, unknown, exempt }

class RequiredDocumentEvidenceItem {
  const RequiredDocumentEvidenceItem._({
    required this.id,
    required this.name,
    required this.scope,
    required this.state,
    required this.evidenceKey,
    required this.statusLabel,
  });

  final String id;
  final String name;
  final String scope;
  final RequiredDocumentEvidenceState state;
  final String? evidenceKey;
  final String statusLabel;
}

/// Validated receipt data only. Callers must still match its identity fields to
/// the company and captured live session that authorized the request.
class RequiredDocumentEvidenceSnapshot {
  RequiredDocumentEvidenceSnapshot._({
    required this.companyId,
    required this.workerId,
    required this.actorId,
    required this.sessionId,
    required this.items,
    required this.requiredCount,
    required this.savedCount,
    required this.missingCount,
    required this.unknownCount,
    required this.exemptCount,
    required this.missingNames,
    required this.unknownNames,
  });

  factory RequiredDocumentEvidenceSnapshot.fromJson(Map json) {
    Never invalid(String field) =>
        throw FormatException('Invalid evidence receipt: $field');
    String string(Object? value, String field) {
      if (value is! String || value.trim().isEmpty) { invalid(field); }
      return value;
    }

    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    String identity(String field) {
      final value = string(json[field], field);
      if (!uuid.hasMatch(value)) { invalid(field); }
      return value;
    }

    int count(String field) {
      final value = json[field];
      if (value is! int || value < 0) { invalid(field); }
      return value;
    }

    List<String> names(String field) {
      final value = json[field];
      if (value is! List) { invalid(field); }
      return List<String>.unmodifiable(value.map((v) => string(v, field)));
    }

    if (json['capability_version'] is! int ||
        json['capability_version'] != 1 ||
        json['evidence_contract_version'] is! int ||
        json['evidence_contract_version'] != 1) {
      invalid('version');
    }
    final companyId = identity('company_id');
    final workerId = identity('worker_id');
    final actorId = identity('actor_id');
    final sessionId = identity('session_id');
    final rawItems = json['items'];
    if (rawItems is! List) { invalid('items'); }
    final ids = <String>{};
    final items = <RequiredDocumentEvidenceItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) { invalid('item'); }
      final id = string(raw['requirement_id'], 'requirement_id');
      if (!uuid.hasMatch(id) || !ids.add(id.toLowerCase())) {
        invalid('requirement_id');
      }
      final name = string(raw['name'], 'name');
      final scope = string(raw['scope'], 'scope');
      if (!const {'internal', 'upstream', 'both'}.contains(scope)) {
        invalid('scope');
      }
      final stateName = raw['state'];
      final states = RequiredDocumentEvidenceState.values.where(
        (v) => v.name == stateName,
      );
      if (states.length != 1) { invalid('state'); }
      final state = states.single;
      final statusLabel = raw['status_label'];
      if (statusLabel is! String) { invalid('status_label'); }
      final key = raw['evidence_key'];
      if (key != null && key is! String) { invalid('evidence_key'); }
      if (state == RequiredDocumentEvidenceState.saved &&
          (key == null || (key as String).trim().isEmpty)) {
        invalid('evidence_key');
      }
      items.add(
        RequiredDocumentEvidenceItem._(
          id: id,
          name: name,
          scope: scope,
          state: state,
          evidenceKey: key as String?,
          statusLabel: statusLabel,
        ),
      );
    }
    final requiredCount = count('required_count');
    final savedCount = count('saved_count');
    final missingCount = count('missing_count');
    final unknownCount = count('unknown_count');
    final exemptCount = count('exempt_count');
    int actual(RequiredDocumentEvidenceState state) =>
        items.where((v) => v.state == state).length;
    if (savedCount != actual(RequiredDocumentEvidenceState.saved) ||
        missingCount != actual(RequiredDocumentEvidenceState.missing) ||
        unknownCount != actual(RequiredDocumentEvidenceState.unknown) ||
        exemptCount != actual(RequiredDocumentEvidenceState.exempt) ||
        requiredCount != items.length - exemptCount) {
      invalid('counts');
    }
    final missingNames = names('missing_names');
    final unknownNames = names('unknown_names');
    bool matches(List<String> names, RequiredDocumentEvidenceState state) {
      final expected =
          items.where((v) => v.state == state).map((v) => v.name).toList()
            ..sort();
      final received = names.toList()..sort();
      return expected.length == received.length &&
          List.generate(
            expected.length,
            (i) => expected[i] == received[i],
          ).every((v) => v);
    }

    if (!matches(missingNames, RequiredDocumentEvidenceState.missing) ||
        !matches(unknownNames, RequiredDocumentEvidenceState.unknown)) {
      invalid('names');
    }
    return RequiredDocumentEvidenceSnapshot._(
      companyId: companyId,
      workerId: workerId,
      actorId: actorId,
      sessionId: sessionId,
      items: List.unmodifiable(items),
      requiredCount: requiredCount,
      savedCount: savedCount,
      missingCount: missingCount,
      unknownCount: unknownCount,
      exemptCount: exemptCount,
      missingNames: missingNames,
      unknownNames: unknownNames,
    );
  }

  final String companyId;
  final String workerId;
  final String actorId;
  final String sessionId;
  final List<RequiredDocumentEvidenceItem> items;
  final int requiredCount;
  final int savedCount;
  final int missingCount;
  final int unknownCount;
  final int exemptCount;
  final List<String> missingNames;
  final List<String> unknownNames;
  String labelFor(RequiredDocumentEvidenceItem item) {
    if (items.where((entry) => entry.name == item.name).length < 2) { return item.name; }
    final purpose = switch (item.scope) {
      'internal' => '社内', 'upstream' => '取引会社', _ => '社内・取引会社',
    };
    return '$purpose：${item.name}';
  }

}

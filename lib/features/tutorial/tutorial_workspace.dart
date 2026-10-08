import 'tutorial_evidence_repository.dart' as source;
import 'tutorial_progress.dart' as model;

typedef TutorialSnapshotLoader = Future<source.TutorialEvidenceSnapshot> Function(
  Set<String> availableActionKeys,
);
typedef TutorialOpenAction = Future<void> Function(String actionKey);

class TutorialWorkspace {
  TutorialWorkspace._(this.snapshot, this.progress, this.tasksById);

  final source.TutorialEvidenceSnapshot snapshot;
  final model.TutorialProgress progress;
  final Map<String, source.TutorialEvidenceTask> tasksById;

  static const titles = <String, String>{
    'personal_profile': '本人情報',
    'personnel_profile': '社員情報',
    'personnel_details_recommended': '社員情報の追加項目',
    'company_profile': '会社情報',
    'company_details_recommended': '会社情報の追加項目',
    'required_documents': '必要書類',
    'company_payroll_policy': '会社の給与方針・確認者',
    'company_document_selection': '会社の必要書類指定',
    'personal_qualifications': '本人の資格',
    'setup_trade_companies': '取引会社',
    'setup_subcontractors': '下請け会社',
    'setup_site_register': '現場',
    'setup_payroll_settings': '個別給与設定',
    'setup_payment_certificate_settings': '支払証明書設定',
  };

  factory TutorialWorkspace.fromSnapshot(source.TutorialEvidenceSnapshot snapshot) {
    final definitions = <model.TutorialTask>[];
    final evidence = <String, model.TutorialEvidence>{};
    final byId = <String, source.TutorialEvidenceTask>{};
    for (final task in snapshot.tasks) {
      if (byId.containsKey(task.key)) {
        throw StateError('Duplicate tutorial evidence task: ${task.key}');
      }
      byId[task.key] = task;
      final checkpointIds = <String>[];
      for (final checkpoint in task.checkpoints) {
        final id = '${task.key}:${checkpoint.key}';
        if (evidence.containsKey(id)) {
          throw StateError('Duplicate tutorial evidence checkpoint: $id');
        }
        checkpointIds.add(id);
        evidence[id] = switch (checkpoint.state) {
          source.TutorialEvidenceState.saved =>
            checkpoint.evidenceKey?.trim().isNotEmpty == true
              ? model.TutorialEvidence.saved(checkpoint.evidenceKey!)
              : const model.TutorialEvidence.unknown(),
          source.TutorialEvidenceState.missing => const model.TutorialEvidence.missing(),
          source.TutorialEvidenceState.unknown => const model.TutorialEvidence.unknown(),
          source.TutorialEvidenceState.notApplicable => const model.TutorialEvidence.notApplicable(),
        };
      }
      if (checkpointIds.isEmpty) {
        checkpointIds.add('${task.key}:unloaded');
      }
      definitions.add(model.TutorialTask(
        id: task.key, title: titles[task.key] ?? '準備項目',
        roles: model.TutorialRole.values,
        requirement: task.requiredForCompletion
          ? model.TutorialRequirement.required : model.TutorialRequirement.recommended,
        applicability: snapshot.role == null
          ? model.TutorialApplicability.unknown : model.TutorialApplicability.applicable,
        checkpointIds: checkpointIds,
        priority: task.key == 'personal_profile' || task.key == 'personnel_profile'
          ? model.TutorialPriority.high
          : task.requiredForCompletion ? model.TutorialPriority.normal : model.TutorialPriority.low,
      ));
    }
    return TutorialWorkspace._(snapshot,
      model.TutorialProgress.evaluate(tasks: definitions,
        role: model.tutorialRoleFromMembership(snapshot.role ?? ''),
        evidence: evidence, now: DateTime.now()), Map.unmodifiable(byId));
  }

  /// A known all-inapplicable required set is complete; an empty registry is not.
  bool get canCompleteInitial => snapshot.role != null &&
      snapshot.tasks.any((task) => task.requiredForCompletion) &&
      progress.required.isKnown && progress.required.missing == 0 &&
      progress.required.externalWaiting == 0;

  String? get nextTaskId {
    for (final task in progress.tasks) {
      if (task.task.requirement == model.TutorialRequirement.required &&
          !task.counts.isComplete && task.counts.total > 0) {
        return task.task.id;
      }
    }
    for (final task in progress.tasks) {
      if (!task.counts.isComplete && task.counts.total > 0) {
        return task.task.id;
      }
    }
    return progress.tasks.isEmpty ? null : progress.tasks.first.task.id;
  }
}

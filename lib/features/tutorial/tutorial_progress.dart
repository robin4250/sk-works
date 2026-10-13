/// Tutorial progress is computed from persisted evidence, never page views.
enum TutorialRole { employee, subAdministrator, administrator }

enum TutorialRequirement { required, recommended, optional }

enum TutorialApplicability { applicable, notApplicable, unknown }

enum TutorialEvidenceState { saved, missing, unknown, externalWaiting, notApplicable }

enum TutorialProgressState { unknown, empty, pending, inProgress, externalWaiting, completed }

enum TutorialPriority { urgent, high, normal, low }

TutorialRole tutorialRoleFromMembership(String role) => switch (role) {
  'owner' || 'admin' => TutorialRole.administrator,
  'manager' => TutorialRole.subAdministrator,
  _ => TutorialRole.employee,
};

class TutorialEvidence {
  const TutorialEvidence._(this.state, this.persistedEvidenceId, this.waitingReason);

  /// The caller supplies an ID only after successfully reading saved evidence.
  factory TutorialEvidence.saved(String persistedEvidenceId) {
    if (persistedEvidenceId.trim().isEmpty) {
      throw ArgumentError.value(persistedEvidenceId, 'persistedEvidenceId');
    }
    return TutorialEvidence._(TutorialEvidenceState.saved, persistedEvidenceId, null);
  }

  const TutorialEvidence.missing()
      : this._(TutorialEvidenceState.missing, null, null);
  const TutorialEvidence.unknown()
      : this._(TutorialEvidenceState.unknown, null, null);
  const TutorialEvidence.notApplicable()
      : this._(TutorialEvidenceState.notApplicable, null, null);
  const TutorialEvidence.externalWaiting(String reason)
      : this._(TutorialEvidenceState.externalWaiting, null, reason);

  final TutorialEvidenceState state;
  final String? persistedEvidenceId;
  final String? waitingReason;
}

class TutorialTask {
  TutorialTask({
    required this.id,
    required this.title,
    required Iterable<TutorialRole> roles,
    required this.requirement,
    required Iterable<String> checkpointIds,
    this.applicability = TutorialApplicability.applicable,
    this.dueAt,
    this.priority = TutorialPriority.normal,
  }) : roles = Set<TutorialRole>.unmodifiable(roles),
       checkpointIds = List<String>.unmodifiable(checkpointIds.toSet()) {
    if (id.trim().isEmpty || this.checkpointIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError('Task and checkpoint IDs must be nonempty.');
    }
    if (this.checkpointIds.isEmpty) {
      throw ArgumentError('A task needs at least one evidence checkpoint.');
    }
  }

  final String id;
  final String title;
  final Set<TutorialRole> roles;
  final TutorialRequirement requirement;
  final List<String> checkpointIds;
  final TutorialApplicability applicability;
  final DateTime? dueAt;
  final TutorialPriority priority;

  bool _sameDefinition(TutorialTask other) => title == other.title &&
      requirement == other.requirement && applicability == other.applicability &&
      dueAt == other.dueAt && priority == other.priority &&
      roles.length == other.roles.length && roles.containsAll(other.roles) &&
      checkpointIds.length == other.checkpointIds.length &&
      checkpointIds.toSet().containsAll(other.checkpointIds);
}

class TutorialCounts {
  const TutorialCounts({
    required this.total,
    required this.completed,
    required this.missing,
    required this.unknown,
    required this.externalWaiting,
    this.unknownApplicabilityTasks = 0,
    this.excludedNotApplicableCheckpoints = 0,
  });

  /// Known applicable checkpoints only; no weights are applied.
  final int total;
  final int completed;
  final int missing;
  final int unknown;
  final int externalWaiting;
  final int unknownApplicabilityTasks;
  final int excludedNotApplicableCheckpoints;

  bool get isKnown => unknown == 0 && unknownApplicabilityTasks == 0;
  int get knownRemaining => missing + externalWaiting;
  int? get remaining => isKnown ? total - completed : null;
  double? get percentage => !isKnown || total == 0 ? null : completed * 100 / total;
  bool get isComplete => isKnown && total > 0 && completed == total;

  TutorialProgressState get state {
    if (!isKnown) {
      return TutorialProgressState.unknown;
    }
    if (total == 0) {
      return TutorialProgressState.empty;
    }
    if (isComplete) {
      return TutorialProgressState.completed;
    }
    if (missing == 0 && externalWaiting > 0) {
      return TutorialProgressState.externalWaiting;
    }
    return completed > 0 ? TutorialProgressState.inProgress : TutorialProgressState.pending;
  }
}

class TutorialTaskProgress {
  const TutorialTaskProgress(this.task, this.counts);
  final TutorialTask task;
  final TutorialCounts counts;

  /// Deadlines affect ordering, never the percentage or saved records.
  bool isOverdue(DateTime now) => !counts.isComplete &&
      task.dueAt != null && task.dueAt!.isBefore(now);
}

class TutorialProgress {
  TutorialProgress._({
    required this.required,
    required this.recommended,
    required this.overall,
    required Iterable<TutorialTaskProgress> tasks,
    required this.excludedOptionalTasks,
    required this.excludedNotApplicableTasks,
    required this.excludedOtherRoleTasks,
  }) : tasks = List<TutorialTaskProgress>.unmodifiable(tasks);

  final TutorialCounts required;
  final TutorialCounts recommended;
  final TutorialCounts overall;
  final List<TutorialTaskProgress> tasks;
  final int excludedOptionalTasks;
  final int excludedNotApplicableTasks;
  final int excludedOtherRoleTasks;

  factory TutorialProgress.evaluate({
    required Iterable<TutorialTask> tasks,
    required TutorialRole role,
    required Map<String, TutorialEvidence> evidence,
    required DateTime now,
  }) {
    final unique = <String, TutorialTask>{};
    for (final task in tasks) {
      final previous = unique[task.id];
      if (previous != null && !previous._sameDefinition(task)) {
        throw ArgumentError('Conflicting tutorial definitions for ${task.id}.');
      }
      unique.putIfAbsent(task.id, () => task);
    }
    final results = <TutorialTaskProgress>[];
    final owners = <String, String>{};
    var optional = 0;
    var notApplicable = 0;
    var otherRole = 0;
    for (final task in unique.values) {
      if (!task.roles.contains(role)) { otherRole++; continue; }
      if (task.requirement == TutorialRequirement.optional) { optional++; continue; }
      if (task.applicability == TutorialApplicability.notApplicable) {
        notApplicable++; continue;
      }
      if (task.applicability == TutorialApplicability.unknown) {
        results.add(TutorialTaskProgress(task, const TutorialCounts(
          total: 0, completed: 0, missing: 0, unknown: 0, externalWaiting: 0,
          unknownApplicabilityTasks: 1,
        )));
        continue;
      }
      var completed = 0;
      var missing = 0;
      var unknown = 0;
      var waiting = 0;
      var excludedCheckpoints = 0;
      for (final checkpointId in task.checkpointIds) {
        final owner = owners[checkpointId];
        if (owner != null && owner != task.id) {
          throw ArgumentError('Checkpoint $checkpointId belongs to multiple tasks.');
        }
        owners[checkpointId] = task.id;
        switch (evidence[checkpointId]?.state ?? TutorialEvidenceState.unknown) {
          case TutorialEvidenceState.saved: completed++;
          case TutorialEvidenceState.missing: missing++;
          case TutorialEvidenceState.unknown: unknown++;
          case TutorialEvidenceState.externalWaiting: waiting++;
          case TutorialEvidenceState.notApplicable: excludedCheckpoints++;
        }
      }
      results.add(TutorialTaskProgress(task, TutorialCounts(
        total: task.checkpointIds.length - excludedCheckpoints, completed: completed, missing: missing,
        unknown: unknown, externalWaiting: waiting,
        excludedNotApplicableCheckpoints: excludedCheckpoints,
      )));
    }
    results.sort((a, b) {
      final completion = (a.counts.isComplete ? 1 : 0).compareTo(b.counts.isComplete ? 1 : 0);
      if (completion != 0) {
        return completion;
      }
      final overdue = (b.isOverdue(now) ? 1 : 0).compareTo(a.isOverdue(now) ? 1 : 0);
      if (overdue != 0) {
        return overdue;
      }
      final priority = a.task.priority.index.compareTo(b.task.priority.index);
      if (priority != 0) {
        return priority;
      }
      final aDue = a.task.dueAt;
      final bDue = b.task.dueAt;
      if (aDue != null && bDue != null) {
        final due = aDue.compareTo(bDue);
        if (due != 0) {
          return due;
        }
      } else if (aDue != null || bDue != null) {
        return aDue != null ? -1 : 1;
      }
      return a.task.id.compareTo(b.task.id);
    });
    TutorialCounts sum(Iterable<TutorialTaskProgress> selected) {
      var total = 0, completed = 0, missing = 0, unknown = 0, waiting = 0, unknownTasks = 0, excludedCheckpoints = 0;
      for (final task in selected) {
        total += task.counts.total; completed += task.counts.completed;
        missing += task.counts.missing; unknown += task.counts.unknown;
        waiting += task.counts.externalWaiting;
        unknownTasks += task.counts.unknownApplicabilityTasks;
        excludedCheckpoints += task.counts.excludedNotApplicableCheckpoints;
      }
      return TutorialCounts(total: total, completed: completed, missing: missing,
        unknown: unknown, externalWaiting: waiting, unknownApplicabilityTasks: unknownTasks,
        excludedNotApplicableCheckpoints: excludedCheckpoints);
    }
    return TutorialProgress._(
      required: sum(results.where((t) => t.task.requirement == TutorialRequirement.required)),
      recommended: sum(results.where((t) => t.task.requirement == TutorialRequirement.recommended)),
      overall: sum(results), tasks: results, excludedOptionalTasks: optional,
      excludedNotApplicableTasks: notApplicable, excludedOtherRoleTasks: otherRole,
    );
  }
}

/// Guide navigation is separate from stored evidence and business data.
class TutorialGuideSession {
  TutorialGuideSession({required Iterable<String> taskIds, this.position = 0})
      : taskIds = List<String>.unmodifiable(taskIds.toSet()) {
    if (position < 0 || (this.taskIds.isNotEmpty && position >= this.taskIds.length) ||
        (this.taskIds.isEmpty && position != 0)) {
      throw RangeError.value(position, 'position');
    }
  }
  final List<String> taskIds;
  final int position;
  String? get currentTaskId => taskIds.isEmpty ? null : taskIds[position];

  /// This restarts explanations only. No evidence is accepted or mutated.
  TutorialGuideSession restart() => TutorialGuideSession(taskIds: taskIds);
  TutorialGuideSession open(String taskId) {
    final index = taskIds.indexOf(taskId);
    if (index < 0) {
      throw ArgumentError.value(taskId, 'taskId');
    }
    return TutorialGuideSession(taskIds: taskIds, position: index);
  }
}

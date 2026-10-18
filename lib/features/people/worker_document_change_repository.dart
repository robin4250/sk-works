import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

bool _uuid(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
    ).hasMatch(value);

bool _date(Object? value) =>
    value is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    DateTime.tryParse(value)?.toIso8601String().substring(0, 10) == value;

/// Fixed document change command; retained before the first prepare attempt.
/// The caller must retain the fixed command before its first prepare attempt.
class WorkerDocumentChangeCommand {
  WorkerDocumentChangeCommand({
    required this.requestId,
    required this.targetId,
    required this.companyId,
    required this.workerId,
    required this.requirementId,
    required this.requestedBy,
    required this.expectedUpdatedAt,
    required List<String> paths,
    required this.expiresAt,
    required this.notes,
  }) : paths = List.unmodifiable(paths) {
    for (final id in [
      requestId,
      targetId,
      companyId,
      workerId,
      requirementId,
      requestedBy,
    ]) {
      if (!_uuid(id)) throw const FormatException('Invalid document target');
    }
    if (!RegExp(
          r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(expectedUpdatedAt) ||
        DateTime.tryParse(expectedUpdatedAt) == null ||
        (expiresAt != null && !_date(expiresAt)) ||
        paths.length > 20 ||
        paths.toSet().length != paths.length ||
        paths.any((p) => p.trim().isEmpty) ||
        notes != notes?.trim()) {
      throw const FormatException('Invalid document change');
    }
  }
  final String requestId,
      targetId,
      companyId,
      workerId,
      requirementId,
      requestedBy;
  final String expectedUpdatedAt;
  final List<String> paths;
  final String? expiresAt, notes;
  Map<String, dynamic> get proposed => {
    'attachment_paths': paths,
    'expires_at': expiresAt,
    'notes': notes,
  };
  Map<String, dynamic> get preparePayload => {
    'request_id': requestId,
    'status_id': targetId,
    'expected_updated_at': expectedUpdatedAt,
    'proposed': proposed,
  };
}

class WorkerDocumentChangeCapability {
  const WorkerDocumentChangeCapability(this.available);
  final bool available;
  factory WorkerDocumentChangeCapability.parse(Object? raw) {
    if (raw is! Map ||
        raw.length != 5 ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['change_requests_available'] is! bool ||
        raw['new_upload_available'] != false ||
        raw['max_photos'] is! int ||
        raw['max_photos'] != 20 ||
        raw['self_approval_allowed'] != false) {
      return const WorkerDocumentChangeCapability(false);
    }
    return WorkerDocumentChangeCapability(
      raw['change_requests_available'] == true,
    );
  }
}

class WorkerDocumentChangeReceipt {
  const WorkerDocumentChangeReceipt(this.status, this.canReview);
  final String status;
  final bool canReview;
  factory WorkerDocumentChangeReceipt.parse(
    Object? raw,
    WorkerDocumentChangeCommand command,
  ) {
    if (raw is! Map ||
        raw['version'] is! int ||
        raw['version'] != 1 ||
        raw['id'] != command.requestId ||
        raw['target_id'] != command.targetId ||
        raw['company_id'] != command.companyId ||
        raw['worker_id'] != command.workerId ||
        raw['requirement_id'] != command.requirementId ||
        raw['requested_by'] != command.requestedBy ||
        ![
          'draft',
          'pending',
          'approved',
          'rejected',
          'cancelled',
        ].contains(raw['status']) ||
        raw['can_review'] is! bool ||
        raw['previous'] is! Map ||
        raw['proposed'] is! Map) {
      throw const FormatException('Unavailable document change');
    }
    final old = raw['previous'] as Map;
    if (old['id'] != command.targetId ||
        old['company_id'] != command.companyId ||
        old['worker_id'] != command.workerId ||
        old['requirement_id'] != command.requirementId ||
        DateTime.tryParse(old['updated_at']?.toString() ?? '') !=
            DateTime.tryParse(command.expectedUpdatedAt)) {
      throw const FormatException('Mismatched document snapshot');
    }
    final next = raw['proposed'] as Map;
    final paths = next['attachment_paths'];
    if (next.length != 3 ||
        !next.keys.every(
          ['attachment_paths', 'expires_at', 'notes'].contains,
        ) ||
        paths is! List ||
        paths.length != command.paths.length ||
        next['notes'] != command.notes ||
        next['expires_at'] != command.expiresAt) {
      throw const FormatException('Mismatched document proposal');
    }
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] != command.paths[i]) {
        throw const FormatException('Mismatched document photos');
      }
    }
    return WorkerDocumentChangeReceipt(
      raw['status'] as String,
      raw['can_review'] as bool,
    );
  }
}

class WorkerDocumentChangeEntry {
  WorkerDocumentChangeEntry(this.command, this.receipt, this.previous);
  final WorkerDocumentChangeCommand command;
  final WorkerDocumentChangeReceipt receipt;
  final Map<String, dynamic> previous;
  factory WorkerDocumentChangeEntry.parse(Object? raw) {
    if (raw is! Map || raw['previous'] is! Map || raw['proposed'] is! Map) {
      throw const FormatException('Invalid document request');
    }
    final old = Map<String, dynamic>.from(raw['previous'] as Map);
    final next = raw['proposed'] as Map;
    if (!['not_submitted','submitted','verified','missing','expired'].contains(old['status']) ||
        old['original_verified'] is! bool ||
        old['attachment_paths'] is! List ||
        (old['notes'] != null && old['notes'] is! String) ||
        (old['expires_at'] != null && !_date(old['expires_at']))) {
      throw const FormatException('Invalid previous document');
    }
    final oldPaths = (old['attachment_paths'] as List);
    if (oldPaths.length > 20 || oldPaths.any((p) => p is! String || p.trim().isEmpty) ||
        oldPaths.toSet().length != oldPaths.length ||
        (old['attachment_path'] != null && (old['attachment_path'] is! String || (old['attachment_path'] as String).trim().isEmpty))) {
      throw const FormatException('Invalid previous photos');
    }
    final retained = oldPaths.isNotEmpty ? oldPaths : [if (old['attachment_path'] != null) old['attachment_path']];
    final command = WorkerDocumentChangeCommand(
      requestId: raw['id'] as String,
      targetId: raw['target_id'] as String,
      companyId: raw['company_id'] as String,
      workerId: raw['worker_id'] as String,
      requirementId: raw['requirement_id'] as String,
      requestedBy: raw['requested_by'] as String,
      expectedUpdatedAt: old['updated_at'] as String,
      paths: (next['attachment_paths'] as List).cast<String>(),
      expiresAt: next['expires_at'] as String?,
      notes: next['notes'] as String?,
    );
    if (command.paths.any((path) => !retained.contains(path))) throw const FormatException('New uploads unavailable');
    return WorkerDocumentChangeEntry(
      command,
      WorkerDocumentChangeReceipt.parse(raw, command),
      old,
    );
  }
}

/// Actor changes invalidate this instance, including actor A → B → A.
/// Missing RPCs, errors and unknown results never fall back to direct updates.
class WorkerDocumentChangeRepository {
  WorkerDocumentChangeRepository(SupabaseClient client)
    : this.forTesting(
        actor: () => client.auth.currentUser?.id,
        changes: client.auth.onAuthStateChange.map((_) {}),
        rpc: (action, data) => client.rpc(
          'worker_document_change',
          params: {'p_action': action, 'p_data': data},
        ),
      );
  WorkerDocumentChangeRepository.forTesting({
    required String? Function() actor,
    required Stream<void> changes,
    required Future<Object?> Function(String, Map<String, dynamic>) rpc,
  }) : _actor = actor,
       _rpc = rpc,
       _initialActor = actor() {
    _subscription = changes.listen(
      (_) {
        if (_actor() != _initialActor) _invalidate();
      },
      onError: (Object _) {
        _invalidate();
      },
      onDone: () {
        _invalidate();
      },
    );
  }
  final String? Function() _actor;
  final Future<Object?> Function(String, Map<String, dynamic>) _rpc;
  final String? _initialActor;
  late final StreamSubscription<void> _subscription;
  final _invalidations = StreamController<void>.broadcast(sync: true);
  Stream<void> get invalidations => _invalidations.stream;
  void _invalidate() {
    if (_invalid) return;
    _invalid = true;
    _invalidations.add(null);
  }

  bool _invalid = false;
  bool _busy = false;
  bool get isCurrentActor =>
      !_invalid && _initialActor != null && _actor() == _initialActor;

  void _check() {
    if (_invalid || _initialActor == null || _actor() != _initialActor) {
      throw StateError('ログインが変更されました。書類の画面を開き直してください。');
    }
  }

  Future<Object?> _call(String action, Map<String, dynamic> data) async {
    _check();
    try {
      final value = await _rpc(action, data);
      _check();
      return value;
    } catch (_) {
      _check();
      rethrow;
    }
  }

  Future<WorkerDocumentChangeCapability> capability() async {
    try {
      return WorkerDocumentChangeCapability.parse(
        await _call('capability', {}),
      );
    } on PostgrestException catch (error) {
      _check();
      if (['PGRST202', '42883'].contains(error.code)) {
        return const WorkerDocumentChangeCapability(false);
      }
      rethrow;
    }
  }

  Future<List<WorkerDocumentChangeEntry>> list(String companyId) async {
    if (!_uuid(companyId)) throw const FormatException('Invalid company');
    final raw = await _call('list', {});
    if (raw is! List) throw const FormatException('Invalid request list');
    return raw
        .map(WorkerDocumentChangeEntry.parse)
        .where((entry) => entry.command.companyId == companyId)
        .toList(growable: false);
  }

  Future<WorkerDocumentChangeReceipt> prepare(
    WorkerDocumentChangeCommand command,
  ) => _command('prepare', command, command.preparePayload, own: true);
  Future<WorkerDocumentChangeReceipt> submit(
    WorkerDocumentChangeCommand command,
  ) =>
      _command('submit', command, {'request_id': command.requestId}, own: true);
  Future<WorkerDocumentChangeReceipt> cancel(
    WorkerDocumentChangeCommand command,
  ) =>
      _command('cancel', command, {'request_id': command.requestId}, own: true);
  Future<WorkerDocumentChangeReceipt> detail(
    WorkerDocumentChangeCommand command,
  ) async => WorkerDocumentChangeReceipt.parse(
    await _call('detail', {'request_id': command.requestId}),
    command,
  );
  Future<WorkerDocumentChangeReceipt> review(
    WorkerDocumentChangeCommand command, {
    required bool approve,
    String? reason,
  }) {
    if (_initialActor == command.requestedBy ||
        (!approve && (reason?.trim().isEmpty ?? true))) {
      throw StateError('この書類変更は承認できません。');
    }
    return _command(approve ? 'approve' : 'reject', command, {
      'request_id': command.requestId,
      if (!approve) 'reason': reason!.trim(),
    });
  }

  Future<WorkerDocumentChangeReceipt> _command(
    String action,
    WorkerDocumentChangeCommand command,
    Map<String, dynamic> data, {
    bool own = false,
  }) async {
    _check();
    if (_busy || (own && _initialActor != command.requestedBy)) {
      throw StateError('同じ申請の結果を先に確認してください。');
    }
    _busy = true;
    try {
      final receipt = WorkerDocumentChangeReceipt.parse(
        await _call(action, data),
        command,
      );
      final allowed = switch (action) {
        'prepare' => ['draft', 'pending', 'approved', 'rejected', 'cancelled'],
        'submit' => ['pending', 'approved', 'rejected'],
        'cancel' => ['cancelled'],
        'approve' => ['approved'],
        'reject' => ['rejected'],
        _ => <String>[],
      };
      if (!allowed.contains(receipt.status)) {
        throw const FormatException('Unconfirmed document operation');
      }
      return receipt;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    _invalidate();
    await _subscription.cancel();
    await _invalidations.close();
  }
}

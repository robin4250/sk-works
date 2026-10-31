import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'worker_document_admin_correction_page.dart';
import 'worker_document_admin_correction_repository.dart';

/// Scoped journal recovery also works without the original status-list row.
Future<void> recoverPendingWorkerDocumentAdminCorrections({
  required BuildContext context,
  required Future<List<String>> Function() pendingTargets,
  required Future<WorkerDocumentAdminCorrectionRepository> Function(String)
  createRepository,
  required bool Function() isCurrent,
}) async {
  final targets = await pendingTargets();
  if (!context.mounted || !isCurrent()) {
    throw StateError('ログイン・会社の状態が変わりました。');
  }
  if (targets.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('結果確認が必要な書類訂正はありません。')));
    return;
  }
  final target = targets.length == 1
      ? targets.single
      : await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('未確認の書類訂正'),
            children: [
              for (var i = 0; i < targets.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, targets[i]),
                  child: Text('書類訂正 ${i + 1}'),
                ),
            ],
          ),
        );
  if (target == null) {
    return;
  }
  if (!context.mounted || !isCurrent()) {
    throw StateError('ログイン・会社の状態が変わりました。');
  }
  final repository = await createRepository(target);
  if (!context.mounted || !isCurrent()) {
    repository.dispose();
    throw StateError('ログイン・会社の状態が変わりました。');
  }
  await openWorkerDocumentAdminCorrection(
    context: context,
    repository: repository,
    snapshot: const {},
    documentName: '未確認の書類訂正',
    isCurrentTarget: isCurrent,
  );
}

/// False preserves the existing employee-request route. Only an exact server
/// purpose capability can select administrator-own correction.
Future<bool> openWorkerDocumentAdminCorrection({
  required BuildContext context,
  required WorkerDocumentAdminCorrectionRepository repository,
  required Map<String, dynamic> snapshot,
  required String documentName,
  required bool Function() isCurrentTarget,
}) async {
  try {
    // Recovery is independent of the current new-write capability. In
    // particular OFF must never strand an uncertain fixed operation ID or
    // redirect it into the old employee request workflow.
    if (repository.pendingRequest() != null) {
      if (!isCurrentTarget() || !context.mounted) {
        throw StateError('ログイン・会社・書類の状態が変わりました。');
      }
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => WorkerDocumentAdminCorrectionPage(
            repository: repository,
            snapshot: const {},
            documentName: documentName,
            recoveryOnly: true,
          ),
        ),
      );
      return true;
    }
    var available = false;
    try {
      available = await repository.available();
    } on PostgrestException catch (error) {
      // Missing candidate/OFF/ordinary employee do not replace the old route.
      // Transport retirement produces StateError and cannot enter this branch.
      final endpointMissing =
          error.code == 'PGRST202' &&
          RegExp(
            r'^Could not find the function public\.worker_document_admin_self_correction\(p_action, ?p_data\) in the schema cache\.?$',
          ).hasMatch(error.message);
      final purposeNotApplicable =
          error.code == '42501' &&
          const {
            'administrator required',
            'people permission required',
            'own active worker required',
          }.contains(error.message);
      if (!endpointMissing && !purposeNotApplicable) {
        rethrow;
      }
    }
    if (!isCurrentTarget() || !context.mounted) {
      throw StateError('ログイン・会社・書類の状態が変わりました。');
    }
    if (!available) {
      return false;
    }
    // The displayed list projection is not a full-row CAS snapshot. Obtain the
    // authoritative current row through the purpose-specific authorized RPC.
    final inspected = await repository.inspect();
    if (!isCurrentTarget() ||
        !context.mounted ||
        inspected['worker_id'] != snapshot['worker_id'] ||
        inspected['requirement_id'] != snapshot['requirement_id']) {
      throw StateError('ログイン・会社・書類の状態が変わりました。');
    }
    final frozen = jsonDecode(jsonEncode(inspected)) as Map<String, dynamic>;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkerDocumentAdminCorrectionPage(
          repository: repository,
          snapshot: frozen,
          documentName: documentName,
        ),
      ),
    );
    return true;
  } finally {
    repository.dispose();
  }
}

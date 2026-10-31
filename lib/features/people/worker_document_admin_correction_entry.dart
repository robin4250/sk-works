import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'worker_document_admin_correction_page.dart';
import 'worker_document_admin_correction_repository.dart';

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
    var available = false;
    try {
      available = await repository.available();
    } on PostgrestException catch (error) {
      // Missing candidate/OFF/ordinary employee do not replace the old route.
      // Transport retirement produces StateError and cannot enter this branch.
      if (!['PGRST202', '42883', '42501'].contains(error.code)) {
        rethrow;
      }
    }
    if (!isCurrentTarget() || !context.mounted) {
      throw StateError('ログイン・会社・書類の状態が変わりました。');
    }
    if (!available) {
      return false;
    }
    final frozen = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
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

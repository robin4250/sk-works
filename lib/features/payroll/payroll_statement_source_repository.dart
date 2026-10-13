import 'package:supabase_flutter/supabase_flutter.dart';
import 'payroll_confirmation_repository.dart';
import 'payroll_review_repository.dart';
import 'payroll_statement_repository.dart';

class PayrollStatementSource {
  const PayrollStatementSource(this.statement, this.confirmation);
  final PayrollStatementRecord statement;
  final PayrollConfirmationStatus? confirmation;
}

/// Resolves a fresh, authorized row before PDF output. Frozen rows never consult
/// the current month's confirmation metadata.
class PayrollStatementSourceRepository {
  PayrollStatementSourceRepository({
    required this.readManagement,
    required this.readSelf,
    required this.readConfirmation,
  });
  final Future<List<PayrollStatementRecord>> Function(DateTime) readManagement;
  final Future<List<PayrollStatementRecord>> Function() readSelf;
  final Future<PayrollConfirmationStatus> Function(DateTime) readConfirmation;

  static PayrollStatementSourceRepository? maybeCreate() {
    final review = PayrollReviewRepository.maybeCreate();
    final self = PayrollStatementRepository.maybeCreate();
    final confirmation = PayrollConfirmationRepository.maybeCreate();
    if (review == null || self == null || confirmation == null) return null;
    return PayrollStatementSourceRepository(
      readManagement: (month) async =>
          (await review.loadWorkspace(month)).items.map((item) => item.statement).toList(),
      readSelf: self.loadMyStatements,
      readConfirmation: confirmation.loadStatus,
    );
  }

  PayrollStatementRecord _target(List<PayrollStatementRecord> rows, String id) {
    for (final statement in rows) {
      if (statement.id == id) return statement;
    }
    throw StateError('この給与明細を閲覧できません。');
  }

  bool _selfFallback(Object error) => error is PostgrestException &&
      (error.code == '42501' ||
       (error.code == 'P0001' && error.message == 'payroll review permission required') ||
       ((error.code == 'PGRST202' || error.code == '42883') &&
        error.message.contains('payroll_review_workspace')));

  Future<PayrollStatementSource> load(PayrollStatementRecord original) async {
    PayrollStatementRecord statement;
    try {
      statement = _target(await readManagement(original.periodStart), original.id);
    } catch (error) {
      if (!_selfFallback(error)) rethrow;
      return PayrollStatementSource(_target(await readSelf(), original.id), null);
    }
    if (!statement.isDraft) return PayrollStatementSource(statement, null);
    try {
      return PayrollStatementSource(statement, await readConfirmation(statement.periodStart));
    } catch (error) {
      if (_selfFallback(error)) {
        return PayrollStatementSource(_target(await readSelf(), original.id), null);
      }
      if (error is PostgrestException &&
          (error.code == 'PGRST202' || error.code == '42883') &&
          error.message.contains('payroll_confirmation_status')) {
        return PayrollStatementSource(statement, null);
      }
      rethrow;
    }
  }
}

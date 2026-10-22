import 'dart:async';
import 'package:sk_works/features/payroll/company_common_canonical_publication_command.dart';
import 'package:sk_works/features/payroll/company_common_canonical_publication_repository.dart';
import 'package:sk_works/features/payroll/company_common_payroll_publication_repository.dart';

// Synthetic client behavior fixture. SQL-export conformance is checked separately.
const actor = '00000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000001';
const requestId = '80000000-0000-0000-0000-000000000001';
Map<String, dynamic> base() => {
  'p_company_id': company, 'p_payroll_type': 'monthly', 'p_starts_on': '2026-10-01',
  'p_common_version': 3, 'p_common_source': {'fixture_source': 'original'},
  'p_timeline_version': 0, 'p_legacy_quantities': [],
  'p_individual_reconciliation': CommonPayrollCanonicalPublicationCommand.reconciliation,
};
Map<String, dynamic> timeline({int version = 0}) => {
  'contract_version': 1, 'company_id': company, 'can_edit': true,
  'timeline_version': version, 'common_version': 3, 'common_source': {'fixture_source': 'original'},
  'entries': [if (version == 1) {'version': 1, 'payroll_type': 'monthly',
    'starts_on': '2026-10-01', 'request_id': requestId}],
};
Map<String, dynamic> scope({String status = 'target_draft'}) => {
  'worker_id': '40000000-0000-0000-0000-000000000001',
  'month': '2026-10-01', 'status': status, 'reasons': [], 'selection_classification': [],
};
Map<String, dynamic> previewJson() => {
  'contract_version': 3, 'ready': true, 'preview_token': List.filled(64, 'a').join(),
  'command_base': base(), 'activation_required': true, 'target_count': 1,
  'activation_scope': 'payroll_type', 'activation_mode': 'per_type',
  'activation_blockers': [],
  'excluded_count': 0, 'unresolved_count': 0, 'scopes': [scope()], 'items': [],
  'next_effective_boundary': null, 'timeline': timeline(),
};
CommonPayrollCanonicalPublicationCommand command() =>
    CommonPayrollCanonicalPublicationCommand.fromParams({...base(), 'p_request_id': requestId,
      'p_preview_token': List.filled(64, 'a').join(), 'p_approve_activation': true,
      'p_activation_scope': 'payroll_type'});
Map<String, dynamic> resultJson() => {
  'contract_version': 3, 'company_id': company, 'request_id': requestId,
  'publication_version': 1, 'starts_on': '2026-10-01', 'payroll_type': 'monthly',
  'recalculated_scopes': 1, 'excluded_scopes': 0, 'unresolved_scopes': 0,
  'activation_changed': true, 'scopes': [{...scope(), 'readback_status': 'verified',
    'statement_md5_after': List.filled(32, 'b').join()}], 'timeline': timeline(version: 1),
  'activation_scope': 'payroll_type', 'activation_mode': 'per_type',
};

class FakeCanonicalRepository implements CommonPayrollCanonicalPublicationRepository {
  String? key = 'fixture-session';
  int publishes = 0;
  Object? publishError, receiptError;
  bool found = false;
  Future<void> Function()? beforePublish;
  final receiptCommands = <Map<String, dynamic>>[];
  @override String? get actorId => actor;
  @override String? get sessionKey => key;
  @override Stream<String?> get sessionChanges => const Stream.empty();
  @override Future<bool> available() async => true;
  @override Future<CommonPayrollPublicationState> read(String companyId) async =>
    CommonPayrollPublicationState.parse(timeline(), companyId);
  @override Future<CommonPayrollCanonicalPublicationPreview> preview(Map<String, dynamic> params) async =>
    CommonPayrollCanonicalPublicationPreview.parse(previewJson(), params);
  @override Future<CommonPayrollCanonicalPublicationResult> publish(CommonPayrollCanonicalPublicationCommand value) async {
    publishes++;
    await beforePublish?.call();
    if (publishError != null) throw publishError!;
    return CommonPayrollCanonicalPublicationResult.parse(resultJson(), value);
  }
  @override Future<CommonPayrollCanonicalPublicationResult?> receipt(CommonPayrollCanonicalPublicationCommand value) async {
    receiptCommands.add(value.receiptParams);
    if (receiptError != null) throw receiptError!;
    return found ? CommonPayrollCanonicalPublicationResult.parse(resultJson(), value) : null;
  }
}

import 'dart:io';
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/features/shared/trade_document_template_payload.dart';
import 'package:sk_works/features/payroll/payment_order_resolver.dart';
import 'package:sk_works/features/invoices/invoice_acceptance_resolver.dart';

// Local-only actual resolver checks. No Flutter, HTTP, Supabase or saved data.
void main() {
  var checks = 0;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
    checks++;
  }

  Map<String, dynamic> workspace(String kind) => {
    'source_locked': false,
    'source_blocked': false,
    'source_changed': false,
    'attachment': null,
    'defaults': <String, dynamic>{
      'version': 1,
      'kind': kind,
      'month': '2026-10',
      'issuer': {'name': '発注会社'},
      'counterparty': {'name': '受注会社'},
      'company_seal_snapshot': {
        'version': 1,
        'style': 'legacy',
        'name': '発注会社',
      },
      'company_seal_enabled': false,
      'total_amount_yen': 11000,
      'tax_amount_yen': 1000,
      'invoice_subject': '元帳票の工事',
      'work_address': '元帳票の場所',
    },
    'template': <String, dynamic>{
      'work_name': '設定した工事',
      'work_address': '設定した場所',
      'notes': '設定した特記事項',
    },
  };
  final oldServerPayload = tradeDocumentTemplatePayload({
    'work_name': ' ', 'work_address': '', 'notes': '保存する文面',
  });
  check(oldServerPayload.length == 1 && oldServerPayload['notes'] == '保存する文面',
      'blank optional fields do not block legacy prose saves');
  final configuredPayload = tradeDocumentTemplatePayload({
    'work_name': ' 工事 ', 'work_address': ' 場所 ',
  });
  check(configuredPayload['work_name'] == '工事' && configuredPayload['work_address'] == '場所',
      'nonempty configured defaults are sent');
  final order = workspace('order');
  final resolved = PaymentOrderResolver.resolve(order)!;
  check(resolved.payload['work_name'] == '設定した工事', 'configured work name');
  check(
    resolved.payload['work_address'] == '設定した場所',
    'configured work location',
  );
  check(resolved.payload['notes'] == '設定した特記事項', 'configured notes');
  check(
    resolved.payload['total_amount_yen'] == 11000,
    'source amount retained',
  );
  check(
    order['attachment'] == null,
    'automatic output does not save an appendix',
  );
  (order['template'] as Map).addAll(<String, dynamic>{
    'work_name': ' ',
    'work_address': '',
  });
  final blank = PaymentOrderResolver.resolve(order)!;
  check(blank.payload['work_name'] == '元帳票の工事', 'blank name uses source');
  check(
    blank.payload['work_address'] == '元帳票の場所',
    'blank location uses source',
  );
  order['attachment'] = {'version': 3, 'payload': resolved.payload};
  order['source_locked'] = true;
  check(
    PaymentOrderResolver.resolve(order)!.payload['work_name'] == '設定した工事',
    'saved appendix remains unchanged',
  );
  final acceptance = workspace('acceptance');
  var missing = 0;
  final generated = InvoiceAcceptanceResolver.resolve(
    acceptance,
    issueDate: DateTime(2026, 10, 31),
    onMissingLockedAcceptance: () => missing++,
  );
  check(
    generated?.payload['kind'] == 'acceptance',
    'draft automatically resolves acceptance',
  );
  check(generated?.payload['issue_date'] == '2026-09-30', 'acceptance uses target previous month end');
  check(
    generated?.payload['order_date'] == '2026-09-15',
    'previous month contract date',
  );
  check(missing == 0, 'draft is not reported missing');
  acceptance['source_locked'] = true;
  var missingDateRejected = false;
  try {
    InvoiceAcceptanceResolver.resolve(acceptance, issueDate: null);
  } on StateError {
    missingDateRejected = true;
  }
  check(missingDateRejected, 'missing invoice issue date is rejected');
  var missingParentRejected = false;
  try {
    InvoiceAcceptanceResolver.resolve(acceptance, issueDate: DateTime(2026, 10, 31));
  } on StateError {
    missingParentRejected = true;
  }
  check(missingParentRejected, 'locked invoice requires frozen parent seal');
  final lockedGenerated = InvoiceAcceptanceResolver.resolve(
    acceptance,
    issueDate: DateTime(2026, 10, 31),
    parentSealSnapshot: CompanySealSnapshot.legacy,
    parentSealEnabled: false,
    onMissingLockedAcceptance: () => missing++,
  );
  check(lockedGenerated?.payload['issue_date'] == '2026-09-30',
      'locked source automatically generates with its explicit issue date');
  check(lockedGenerated?.payload['company_seal_enabled'] == false &&
      lockedGenerated?.payload['company_seal_snapshot'] == null,
      'locked source preserves legacy disabled parent seal');
  check(acceptance['attachment'] == null, 'locked generation never saves appendix');
  check(missing == 0, 'locked automatic generation is not reported missing');
  acceptance['attachment'] = {'version': 4, 'payload': generated!.payload};
  check(
    InvoiceAcceptanceResolver.resolve(acceptance, issueDate: null)!.version ==
        4,
    'saved acceptance wins on a locked source',
  );
  stdout.writeln(
    'PASS $checks actual resolver checks; PDF render and production are unverified',
  );
}


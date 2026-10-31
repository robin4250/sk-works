import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_execution.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';

String id(int n) => '93000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  final reference = SiteOrderConsentReference(
    prepare: SiteOrderPendingPrepare(
      siteId: id(1),
      documentId: id(2),
      localId: id(3),
      tradeId: id(4),
      requestId: id(5),
      sessionId: id(6),
    ),
    previewId: id(7),
    operationId: id(8),
    decisionId: id(9),
    bodyHash: 'a' * 64,
  );
  Map<String, dynamic> status() => {
    'contract_version': 1,
    'operation_id': id(8),
    'company_id': id(10),
    'site_id': id(1),
    'document_id': id(2),
    'local_document_id': id(3),
    'trade_company_id': id(4),
    'request_id': id(5),
    'preview_id': id(7),
    'decision_id': id(9),
    'job_id': id(11),
    'body_hash': 'a' * 64,
    'render_hash': 'b' * 64,
    'original_saved': false,
    'original_receipt_id': null,
    'pdf_sha256': null,
    'pdf_byte_length': null,
    'sharing_state': 'not_observed',
    'package_id': null,
    'recipient_company_id': id(12),
    'recipient_approval_state': 'not_checked',
    'device_push_confirmed': false,
    'read_only': true,
    'retry_automatically': false,
    'journal_clearable': false,
  };
  SiteOrderExecutionObservation decode(Map<String, dynamic> value) =>
      SiteOrderExecutionObservation.decode(
        value,
        reference,
        id(10),
        jobId: id(11),
        recipientCompanyId: id(12),
      );
  test(
    'absence and unresolved delivery never permit retry or journal clearance',
    () {
      final absent = decode(status());
      expect(absent.originalSaved, false);
      expect(absent.recipientStored, false);
      expect(absent.retryAutomatically, false);
      expect(absent.journalClearable, false);
      final unresolved = decode(status()..['sharing_state'] = 'unresolved');
      expect(unresolved.unresolved, true);
    },
  );
  test('persisted package requires exact original evidence and does not assert approval', () {
    final value = status()
      ..addAll({
        'original_saved': true,
        'original_receipt_id': id(13),
        'pdf_sha256': 'c' * 64,
        'pdf_byte_length': 123,
        'sharing_state': 'recipient_stored',
        'package_id': id(14),
      });
    expect(decode(value).recipientStored, true);
    for (final change in [
      {'pdf_sha256': 'wrong'},
      {'recipient_company_id': id(99)},
      {'job_id': id(99)},
      {'recipient_approval_state': 'approved'},
      {'journal_clearable': true},
      {'original_saved': false},
      {'read_only': false},
    ]) {
      expect(() => decode({...value, ...change}), throwsStateError);
    }
  });
  test('unknown fields and borrowed purpose evidence fail closed', () {
    for (final change in [
      {'unexpected': true},
      {'operation_id': id(99)},
      {'preview_id': id(99)},
      {'decision_id': id(99)},
      {'body_hash': 'c' * 64},
      {'package_id': id(14)},
      {'pdf_byte_length': 100},
    ]) {
      expect(() => decode({...status(), ...change}), throwsStateError);
    }
  });
  test(
    'stage quarantine survives recreation and retains IDs/digests only',
    () async {
      SharedPreferences.setMockInitialValues({});
      final journal = SiteOrderExecutionJournal();
      expect(await journal.begin(id(20), id(10), reference, 'original'), true);
      expect(
        await SiteOrderExecutionJournal().begin(
          id(20),
          id(10),
          reference,
          'original',
        ),
        false,
      );
      expect(await journal.begin(id(20), id(10), reference, 'share'), true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().length, 2);
      for (final key in prefs.getKeys()) {
        expect(jsonDecode(prefs.getString(key)!), reference.toJson());
        expect(prefs.getString(key), isNot(contains('pdf_bytes')));
      }
      expect(
        () => journal.begin(id(20), id(10), reference, 'unknown'),
        throwsStateError,
      );
    },
  );
}

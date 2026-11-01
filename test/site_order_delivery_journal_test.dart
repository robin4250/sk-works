import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_delivery_journal.dart';
import 'package:sk_works/features/sites/site_order_journal_serial.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_execution.dart';

String id(int n) => '98000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final prepare = SiteOrderPendingPrepare(
  siteId: id(1),
  documentId: id(2),
  localId: id(3),
  tradeId: id(4),
  requestId: id(5),
  sessionId: id(6),
);
final reference = SiteOrderConsentReference(
  prepare: prepare,
  previewId: id(7),
  operationId: id(8),
  decisionId: id(9),
  bodyHash: 'a' * 64,
);
Map<String, dynamic> rawStatus() => {
  'contract_version': 1,
  'operation_id': id(8),
  'company_id': id(11),
  'site_id': id(1),
  'document_id': id(2),
  'local_document_id': id(3),
  'trade_company_id': id(4),
  'request_id': id(5),
  'preview_id': id(7),
  'decision_id': id(9),
  'job_id': id(12),
  'body_hash': 'a' * 64,
  'render_hash': 'b' * 64,
  'original_saved': true,
  'original_receipt_id': id(13),
  'pdf_sha256': 'c' * 64,
  'pdf_byte_length': 100,
  'sharing_state': 'recipient_stored',
  'package_id': id(14),
  'recipient_company_id': id(15),
  'recipient_approval_state': 'not_checked',
  'device_push_confirmed': false,
  'read_only': true,
  'retry_automatically': false,
  'journal_clearable': false,
};
SiteOrderExecutionObservation observation([Map<String, dynamic>? change]) =>
    SiteOrderExecutionObservation.decode(
      {...rawStatus(), ...?change},
      reference,
      id(11),
      jobId: id(12),
      recipientCompanyId: id(15),
    );
String get markerKey =>
    siteOrderDeliveryMarkerKey(id(10), id(11), id(1), id(5));
Future<Map<String, String?>> seed() async {
  await SiteOrderOutgoingJournal().begin(id(10), id(11), prepare);
  await SiteOrderConsentJournal().save(id(10), id(11), reference);
  await SiteOrderExecutionJournal().begin(
    id(10),
    id(11),
    reference,
    'original',
  );
  await SiteOrderExecutionJournal().begin(id(10), id(11), reference, 'share');
  final p = await SharedPreferences.getInstance();
  return {for (final k in p.getKeys()) k: p.getString(k)};
}

Future<void> preserved(Map<String, String?> sources) async {
  final p = await SharedPreferences.getInstance();
  for (final e in sources.entries) {
    expect(p.getString(e.key), e.value);
  }
}

class FaultPreferences implements SharedPreferences {
  FaultPreferences(this.delegate, {required this.cut});
  final SharedPreferences delegate;
  final String cut;
  @override
  Future<void> reload() => delegate.reload();
  @override
  Set<String> getKeys() => delegate.getKeys();
  @override
  bool containsKey(String key) => delegate.containsKey(key);
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  Future<bool> setString(String key, String value) async {
    if (cut == 'before_write') throw StateError('simulated store interruption');
    if (cut == 'write_false') return false;
    final result = await delegate.setString(key, value);
    if (cut == 'after_write') {
      throw StateError('simulated ACK loss after store write');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('single marker archives only sender stage and preserves all raw journal bytes', () async {
    final sources = await seed();
    final journal = SiteOrderDeliveryJournal();
    final record = await journal.record(
      id(10),
      id(11),
      reference,
      observation(),
      verifyScope: () async {},
    );
    expect(record.toJson()['recipient_approval_state'], 'not_checked');
    expect(record.toJson()['stage'], 'sender_delivery_recorded');
    await preserved(sources);
    expect((await SharedPreferences.getInstance()).getKeys().length, 5);
    expect(
      await SiteOrderOutgoingJournal().read(id(10), id(11), id(1)),
      isEmpty,
    );
    expect(
      await SiteOrderConsentJournal().read(id(10), id(11), id(1)),
      isEmpty,
    );
    expect(
      (await journal.read(id(10), id(11), id(1))).single.packageId,
      id(14),
    );
    await expectLater(
      SiteOrderOutgoingJournal().begin(id(10), id(11), prepare),
      throwsStateError,
    );
    await expectLater(
      SiteOrderConsentJournal().save(id(10), id(11), reference),
      throwsStateError,
    );
    await expectLater(
      SiteOrderExecutionJournal().begin(id(10), id(11), reference, 'share'),
      throwsStateError,
    );
    await expectLater(
      SiteOrderOutgoingJournal().resolveRetired(id(10), id(11), prepare),
      throwsStateError,
    );
    final fresh = SiteOrderPendingPrepare(
      siteId: id(1),
      documentId: id(20),
      localId: id(21),
      tradeId: id(4),
      requestId: id(22),
      sessionId: id(6),
    );
    await SiteOrderOutgoingJournal().begin(id(10), id(11), fresh);
    expect(
      (await SiteOrderOutgoingJournal().read(
        id(10),
        id(11),
        id(1),
      )).single.requestId,
      id(22),
    );
    await preserved(sources);
  });
  test(
    'missing marker resurrects original pending record instead of clearing it',
    () async {
      final sources = await seed();
      await SiteOrderDeliveryJournal().record(
        id(10),
        id(11),
        reference,
        observation(),
        verifyScope: () async {},
      );
      final p = await SharedPreferences.getInstance();
      await p.remove(markerKey);
      expect(
        (await SiteOrderOutgoingJournal().read(
          id(10),
          id(11),
          id(1),
        )).single.requestId,
        id(5),
      );
      expect(
        (await SiteOrderConsentJournal().read(
          id(10),
          id(11),
          id(1),
        )).single.decisionId,
        id(9),
      );
      await preserved(sources);
    },
  );
  test('not observed or unresolved delivery never writes a marker', () async {
    final sources = await seed();
    for (final state in ['not_observed', 'unresolved']) {
      await expectLater(
        SiteOrderDeliveryJournal().record(
          id(10),
          id(11),
          reference,
          observation({'sharing_state': state, 'package_id': null}),
          verifyScope: () async {},
        ),
        throwsStateError,
      );
    }
    expect(
      (await SharedPreferences.getInstance()).containsKey(markerKey),
      false,
    );
    await preserved(sources);
  });
  for (final field in [
    'actor_id',
    'company_id',
    'job_id',
    'recipient_company_id',
    'original_receipt_id',
    'package_id',
    'render_hash',
    'pdf_sha256',
  ]) {
    test(
      'foreign or corrupted marker $field cannot hide pending or permit a new order',
      () async {
        await seed();
        await SiteOrderDeliveryJournal().record(
          id(10),
          id(11),
          reference,
          observation(),
          verifyScope: () async {},
        );
        final p = await SharedPreferences.getInstance(),
            raw = jsonDecode(
              (await SharedPreferences.getInstance()).getString(markerKey)!,
            ) as Map<String, dynamic>;
        raw[field] = field.endsWith('hash') || field == 'pdf_sha256'
            ? 'd' * 64
            : id(99);
        await p.setString(markerKey, jsonEncode(raw));
        await expectLater(
          SiteOrderOutgoingJournal().read(id(10), id(11), id(1)),
          throwsStateError,
        );
        final fresh = SiteOrderPendingPrepare(
          siteId: id(1),
          documentId: id(20),
          localId: id(21),
          tradeId: id(4),
          requestId: id(22),
          sessionId: id(6),
        );
        await expectLater(
          SiteOrderOutgoingJournal().begin(id(10), id(11), fresh),
          throwsStateError,
        );
      },
    );
  }
  test('source record missing after marker is unknown, never an empty pending success', () async {
    await seed();
    await SiteOrderDeliveryJournal().record(
      id(10),
      id(11),
      reference,
      observation(),
      verifyScope: () async {},
    );
    final p = await SharedPreferences.getInstance();
    await p.remove(
      'sko.site_order.outgoing.v1.${id(10)}.${id(11)}.${id(1)}.${id(5)}',
    );
    await expectLater(
      SiteOrderConsentJournal().read(id(10), id(11), id(1)),
      throwsStateError,
    );
    await expectLater(
      SiteOrderDeliveryJournal().read(id(10), id(11), id(1)),
      throwsStateError,
    );
  });
  for (final cut in ['before_write', 'write_false', 'after_write']) {
    test(
      'storage interruption $cut retains original bytes and needs explicit fresh recovery',
      () async {
        final sources = await seed(), p = await SharedPreferences.getInstance();
        final journal = SiteOrderDeliveryJournal(
          preferences: () async => FaultPreferences(p, cut: cut),
        );
        await expectLater(
          journal.record(
            id(10),
            id(11),
            reference,
            observation(),
            verifyScope: () async {},
          ),
          throwsStateError,
        );
        await preserved(sources);
        expect(p.containsKey(markerKey), cut == 'after_write');
        final recovered = await SiteOrderDeliveryJournal().record(
          id(10),
          id(11),
          reference,
          observation(),
          verifyScope: () async {},
        );
        expect(recovered.packageId, id(14));
        await preserved(sources);
      },
    );
  }
  for (final cut in [1, 2, 3, 4]) {
    test(
      'scope loss at validation cut $cut never reports success or removes original records',
      () async {
        final sources = await seed();
        var checks = 0;
        await expectLater(
          SiteOrderDeliveryJournal().record(
            id(10),
            id(11),
            reference,
            observation(),
            verifyScope: () async {
              checks++;
              if (checks == cut) throw StateError('scope changed');
            },
          ),
          throwsStateError,
        );
        await preserved(sources);
        await SiteOrderDeliveryJournal().record(
          id(10),
          id(11),
          reference,
          observation(),
          verifyScope: () async {},
        );
        await preserved(sources);
      },
    );
  }
  test(
    'archive and old-purpose begin serialize, so archived intent cannot replay',
    () async {
      await seed();
      final gate = Completer<void>(), entered = Completer<void>();
      var checks = 0, began = false;
      final archived = SiteOrderDeliveryJournal().record(
        id(10),
        id(11),
        reference,
        observation(),
        verifyScope: () async {
          checks++;
          if (checks == 2) {
            entered.complete();
            await gate.future;
          }
        },
      );
      await entered.future;
      final old = SiteOrderExecutionJournal()
          .begin(id(10), id(11), reference, 'share')
          .then((_) => began = true);
      final expectation = expectLater(old, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(began, false);
      gate.complete();
      await archived;
      await expectation;
      expect(began, false);
    },
  );
}

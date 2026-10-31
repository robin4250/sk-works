import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_journal_serial.dart';
import 'package:sk_works/features/sites/site_order_outgoing_journal.dart';
import 'package:sk_works/features/sites/site_order_outgoing_consent.dart';
import 'package:sk_works/features/sites/site_order_outgoing_execution.dart';

String id(int n) => '97000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
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
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'unknown terminal marker prevents every old-purpose mutation intent',
    () async {
      final marker = siteOrderDeliveryMarkerKey(id(10), id(11), id(1), id(5));
      SharedPreferences.setMockInitialValues({
        marker: 'unknown result; not a valid proof',
      });
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
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys(), {marker});
    },
  );
  test(
    'prepare consent and execution share the same in-isolate queue',
    () async {
      final gate = Completer<void>(), entered = Completer<void>();
      final held = siteOrderJournalSerial(() async {
        entered.complete();
        await gate.future;
      });
      await entered.future;
      var prepareDone = false, consentDone = false, executionDone = false;
      final a = SiteOrderOutgoingJournal().begin(id(10), id(11), prepare).then((
        _,
      ) {
        prepareDone = true;
      });
      final b = SiteOrderConsentJournal().save(id(10), id(11), reference).then((
        _,
      ) {
        consentDone = true;
      });
      final c = SiteOrderExecutionJournal()
          .begin(id(10), id(11), reference, 'original')
          .then((_) {
            executionDone = true;
          });
      await Future<void>.delayed(Duration.zero);
      expect([prepareDone, consentDone, executionDone], [false, false, false]);
      gate.complete();
      await Future.wait([held, a, b, c]);
      expect([prepareDone, consentDone, executionDone], [true, true, true]);
      expect((await SharedPreferences.getInstance()).getKeys().length, 3);
    },
  );
  test(
    'failure releases common queue and never turns failure into success',
    () async {
      await expectLater(
        siteOrderJournalSerial<void>(() async {
          throw StateError('simulated interrupted store');
        }),
        throwsStateError,
      );
      expect(
        await SiteOrderConsentJournal().save(id(10), id(11), reference),
        true,
      );
    },
  );
}

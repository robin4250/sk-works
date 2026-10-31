import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/sites/site_order_approval_journal.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const package = '10000000-0000-0000-0000-000000000003';
const preview = '10000000-0000-0000-0000-000000000004';
const request = '10000000-0000-0000-0000-000000000005';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'reply recovery survives restart and is isolated from decisions',
    () async {
      final journal = SiteOrderApprovalJournal.forReplyRecovery();
      await journal.begin(actor, company, package, preview, request);
      expect(
        await SiteOrderApprovalJournal.forReplyRecovery().read(
          actor,
          company,
          package,
        ),
        {'package_id': package, 'preview_id': preview, 'request_id': request},
      );
      expect(
        await SiteOrderApprovalJournal().read(actor, company, package),
        isNull,
      );
      expect(
        await SiteOrderRefusalJournal().read(actor, company, package),
        isNull,
      );
      expect(await journal.read(preview, company, package), isNull);
      await expectLater(
        journal.resolve(actor, company, package, preview),
        throwsStateError,
      );
      await expectLater(
        journal.begin(actor, company, package, preview, request),
        throwsStateError,
      );
      expect(
        (jsonDecode(
          (await SharedPreferences.getInstance()).getString(
            'sko.site_order.reply_recovery.v1.$actor.$company.$package',
          )!,
        ) as Map).keys.toSet(),
        {'package_id', 'preview_id', 'request_id'},
      );
      await journal.resolve(actor, company, package, request);
      expect(await journal.read(actor, company, package), isNull);
    },
  );
  test('refusal uses an independent durable ID-only journal without a fabricated preview', () async {
    final journal = SiteOrderRefusalJournal();
    await journal.begin(actor, company, package, request);
    expect(await SiteOrderRefusalJournal().read(actor, company, package), {
      'package_id': package,
      'request_id': request,
    });
    expect(
      await SiteOrderApprovalJournal().read(actor, company, package),
      isNull,
    );
    await expectLater(
      journal.begin(actor, company, package, preview),
      throwsStateError,
    );
    await expectLater(
      journal.resolve(actor, company, package, preview),
      throwsStateError,
    );
    await journal.resolve(actor, company, package, request);
    expect(await journal.read(actor, company, package), isNull);
  });
  test('unknown approval survives a new page/repository instance with identifiers only', () async {
    final first = SiteOrderApprovalJournal();
    await first.begin(actor, company, package, preview, request);
    final reopened = SiteOrderApprovalJournal();
    expect(await reopened.read(actor, company, package), {
      'package_id': package,
      'preview_id': preview,
      'request_id': request,
    });
    await expectLater(
      reopened.begin(actor, company, package, preview, request),
      throwsStateError,
    );
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(prefs.getKeys().single)!;
    expect((jsonDecode(stored) as Map).keys.toSet(), {
      'package_id',
      'preview_id',
      'request_id',
    });
  });
  test(
    'another actor/company cannot read or clear the quarantined operation',
    () async {
      final journal = SiteOrderApprovalJournal();
      await journal.begin(actor, company, package, preview, request);
      expect(await journal.read(preview, company, package), isNull);
      expect(await journal.read(actor, preview, package), isNull);
      await journal.resolve(preview, company, package, request);
      expect(await journal.read(actor, company, package), isNotNull);
      await expectLater(
        journal.resolve(actor, company, package, preview),
        throwsStateError,
      );
      expect(await journal.read(actor, company, package), isNotNull);
      await journal.resolve(actor, company, package, request);
      expect(await journal.read(actor, company, package), isNull);
    },
  );
  test('two concurrent page instances admit one write, retaining the first operation', () async {
    final first = SiteOrderApprovalJournal(),
        second = SiteOrderApprovalJournal();
    final attempts = await Future.wait([
      first
          .begin(actor, company, package, preview, request)
          .then((_) => true, onError: (_) => false),
      second
          .begin(actor, company, package, package, actor)
          .then((_) => true, onError: (_) => false),
    ]);
    expect(attempts, [true, false]);
    expect(
      (await second.read(actor, company, package))?['request_id'],
      request,
    );
  });
  test(
    'corrupt retained state blocks approval instead of treating it as absent',
    () async {
      SharedPreferences.setMockInitialValues({
        'sko.site_order.approval.v1.$actor.$company.$package':
            '{"request_id":"broken"}',
      });
      final journal = SiteOrderApprovalJournal();
      await expectLater(
        journal.read(actor, company, package),
        throwsStateError,
      );
      await expectLater(
        journal.begin(actor, company, package, preview, request),
        throwsStateError,
      );
    },
  );
}

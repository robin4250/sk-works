import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/referrals/app_referral_composer.dart';

void main() {
  test('failed launch reuses prepared ID and normalized recipient', () async {
    var preparations = 0;
    var launches = 0;
    final recorded = <String>[];
    final composer = AppReferralComposer(
      actorId: () => 'actor-a',
      prepare: (name, phone, friend) async {
        preparations++;
        return {'id': 'invite-1', 'phone': '09012345678', 'message': '招待'};
      },
      openComposer: (uri) async {
        expect(uri.scheme, 'sms');
        expect(uri.path, '09012345678');
        return ++launches > 1;
      },
      recordOpened: (id) async => recorded.add(id),
    );
    expect(await composer.send(name: '佐藤', phone: '+81 90-1234-5678',
        friendInvite: false), AppReferralComposeOutcome.launchFailed);
    expect(await composer.send(name: '佐藤', phone: '09012345678',
        friendInvite: false), AppReferralComposeOutcome.recorded);
    expect(preparations, 1);
    expect(recorded, ['invite-1']);
  });

  test('failed record retries only the record, without reopening SMS', () async {
    var preparations = 0;
    var launches = 0;
    var records = 0;
    final composer = AppReferralComposer(
      actorId: () => 'actor-a',
      prepare: (name, phone, friend) async {
        preparations++;
        return {'id': 'invite-1', 'phone': phone, 'message': '招待'};
      },
      openComposer: (_) async { launches++; return true; },
      recordOpened: (id) async {
        expect(id, 'invite-1');
        if (++records == 1) {
          throw StateError('offline');
        }
      },
    );
    expect(await composer.send(name: '佐藤', phone: '09012345678',
        friendInvite: true), AppReferralComposeOutcome.recordFailed);
    expect(composer.needsRecordRetry, isTrue);
    expect(await composer.send(name: '佐藤', phone: '09012345678',
        friendInvite: true), AppReferralComposeOutcome.recorded);
    expect(preparations, 1);
    expect(launches, 1);
    expect(records, 2);
    expect(composer.needsRecordRetry, isFalse);
  });

  test('overlapping taps cannot prepare two invitations', () async {
    final response = Completer<Map<String, dynamic>>();
    var preparations = 0;
    final composer = AppReferralComposer(
      actorId: () => 'actor-a',
      prepare: (_, _, _) { preparations++; return response.future; },
      openComposer: (_) async => true,
      recordOpened: (_) async {},
    );
    final first = composer.send(name: '佐藤', phone: '09012345678', friendInvite: false);
    expect(await composer.send(name: '佐藤', phone: '09012345678',
        friendInvite: false), AppReferralComposeOutcome.busy);
    response.complete({'id': 'invite-1', 'phone': '09012345678', 'message': '招待'});
    expect(await first, AppReferralComposeOutcome.recorded);
    expect(preparations, 1);
  });

  test('actor change while preparing never opens or records for new actor', () async {
    var actor = 'actor-a';
    var launches = 0;
    final composer = AppReferralComposer(
      actorId: () => actor,
      prepare: (_, phone, _) async {
        actor = 'actor-b';
        return {'id': 'invite-1', 'phone': phone, 'message': '招待'};
      },
      openComposer: (_) async { launches++; return true; },
      recordOpened: (_) async => fail('must not record after actor changes'),
    );
    expect(await composer.send(name: '佐藤', phone: '09012345678',
        friendInvite: false), AppReferralComposeOutcome.actorChanged);
    expect(launches, 0);
  });

  test('changed recipient or referral source prepares a separate invitation', () async {
    var preparations = 0;
    final sources = <bool>[];
    final composer = AppReferralComposer(
      actorId: () => 'actor-a',
      prepare: (_, phone, friend) async {
        sources.add(friend);
        return {'id': 'invite-${++preparations}', 'phone': phone, 'message': '招待'};
      },
      openComposer: (_) async => false,
      recordOpened: (_) async => fail('failed launches must not be recorded'),
    );
    await composer.send(name: '佐藤', phone: '09012345678', friendInvite: false);
    await composer.send(name: '佐藤', phone: '08012345678', friendInvite: false);
    await composer.send(name: '佐藤', phone: '08012345678', friendInvite: true);
    expect(preparations, 3);
    expect(sources, [false, false, true]);
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/referrals/app_referral_composer.dart';

void main() {
  test('authorized invitation routes include TestFlight and their own guide', () async {
    for (final kind in ['employee', 'friends', 'invite', 'partner', 'client']) {
      Uri? opened;
      final composer = AppReferralComposer(
        actorId: () => 'actor-a',
        prepare: (_, __, ___) async => {
          'id': 'invite-$kind', 'phone': '09012345678', 'message': 'Prepared invitation',
        },
        openComposer: (uri) async { opened = uri; return true; },
        recordOpened: (_) async {},
      );
      final guide = 'https://skojapan.com/install/$kind/';
      expect(await composer.send(name: 'Recipient', phone: '09012345678',
        friendInvite: kind == 'friends', distributionKey: 'testflight:$kind', guideUrl: guide), AppReferralComposeOutcome.recorded);
      final body = opened!.queryParameters['body']!;
      expect(body, contains('https://testflight.apple.com/join/1rNHSpdC'));
      expect(body, contains(guide));
      expect(body, contains('iPhone / iPad'));
      expect(body, contains('インストールだけでは登録・会社連携は完了しません'));
    }
  });

  test('public WEB and legacy invitations do not append a beta channel', () async {
    for (final channel in ['public:friend', 'web:friend', '']) {
      Uri? opened;
      final composer = AppReferralComposer(
        actorId: () => 'actor-a',
        prepare: (_, __, ___) async => {
          'id': 'invite-$channel', 'phone': '09012345678',
          'message': 'Authorized channel: https://fixture.example.com/',
        },
        openComposer: (uri) async { opened = uri; return true; },
        recordOpened: (_) async {},
      );
      expect(await composer.send(name: 'Recipient', phone: '09012345678',
        friendInvite: true, distributionKey: channel,
        guideUrl: 'https://skojapan.com/install/friends/'),
        AppReferralComposeOutcome.recorded);
      final body = opened!.queryParameters['body']!;
      expect(body, contains('https://fixture.example.com/'));
      expect(body, contains('https://skojapan.com/install/friends/'));
      expect(body, isNot(contains('testflight.apple.com')));
    }
  });

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

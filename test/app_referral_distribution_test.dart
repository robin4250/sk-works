import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/referrals/app_referral_composer.dart';
import 'package:sk_works/features/referrals/app_referral_page.dart';
import 'package:sk_works/features/referrals/app_referral_repository.dart';

class LegacyChannelRepository extends ChannelRepository {
  @override
  Future<Map<String,dynamic>> load({bool master=false}) async => {
    'can_invite':true, 'distribution_url_ready':true,
    'distribution_url':'https://testflight.apple.com/join/TEST',
    'invitations':<Object>[],
  };
}

class ChannelRepository implements AppReferralRepository {
  @override
  Stream<String?> watchActorChanges() => const Stream.empty();
  @override
  String? get currentActorId => 'channel-actor';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<Map<String,dynamic>> load({bool master=false}) async => {
    'enabled':true,'can_invite':true,'distribution_url_ready':true,
    'distribution_channels':[
      {'key':'testflight','label':'TestFlight版','ready':true},
      {'key':'web','label':'WEB版','ready':true},
      {'key':'public','label':'公開版の案内','ready':false},
    ],
    'invitations':<Object>[],
  };
}

class PublicOnlyChannelRepository extends ChannelRepository {
  @override
  Future<Map<String,dynamic>> load({bool master=false}) async => {
    'enabled': true, 'can_invite': true, 'distribution_url_ready': true,
    'distribution_channels': [
      {'key': 'testflight', 'label': 'TestFlight版', 'ready': false},
      {'key': 'web', 'label': 'WEB版', 'ready': false},
      {'key': 'public', 'label': '公開版の案内', 'ready': true},
    ],
    'invitations': <Object>[],
  };
}

void main() {
  testWidgets('available public channel is selected when internal channels are unavailable', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AppReferralPage(repository: PublicOnlyChannelRepository())));
    await tester.pumpAndSettle();
    expect(find.text('公開版の案内'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '送信')).onPressed, isNotNull);
  });

  testWidgets('missing channel RPC disables friend send but retains company legacy send',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home:AppReferralPage(
      repository:LegacyChannelRepository(),friendInvite:true,
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'送信')).onPressed,isNull);
    await tester.pumpWidget(MaterialApp(home:AppReferralPage(
      key:const ValueKey('company'),repository:LegacyChannelRepository(),invitationKind:'company',
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'送信')).onPressed,isNotNull);
  });

  test('changing distribution after launch failure prepares the selected link anew', () async {
    var prepared=0; var opened=0; final ids=<String>[];
    final composer=AppReferralComposer(
      actorId:()=> 'actor',
      prepare:(n,p,f) async => {'id':'id-${++prepared}','phone':p,'message':'url-$prepared'},
      openComposer:(uri) async { opened++; return opened>2; },
      recordOpened:(id) async { ids.add(id); },
    );
    Future<AppReferralComposeOutcome> send(String channel) => composer.send(
      name:'Recipient',phone:'09012345678',friendInvite:false,distributionKey:channel);
    expect(await send('testflight'),AppReferralComposeOutcome.launchFailed);
    expect(await send('testflight'),AppReferralComposeOutcome.launchFailed);
    expect(prepared,1);
    expect(await send('web'),AppReferralComposeOutcome.recorded);
    expect(prepared,2);
    expect(ids,['id-2']);
  });

  testWidgets('employee additional send keeps contact while switching channel and hides unpublished guide',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home:AppReferralPage(
      repository:ChannelRepository(),invitationKind:'employee',
      initialName:'Employee',initialPhone:'09012345678',
    )));
    await tester.pumpAndSettle();
    expect(find.text('Employee'),findsOneWidget);
    expect(find.text('09012345678'),findsOneWidget);
    expect(find.text('公開版の案内'),findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEB版').last);
    await tester.pumpAndSettle();
    expect(find.text('Employee'),findsOneWidget);
    expect(find.text('09012345678'),findsOneWidget);
    expect(find.text('WEB版'),findsOneWidget);
  });

  testWidgets('friend can select ready TestFlight and WEB while public remains hidden', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AppReferralPage(
      repository: ChannelRepository(), friendInvite: true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('TestFlight版'), findsOneWidget);
    expect(find.text('公開版の案内'), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '送信')).onPressed, isNotNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEB版').last);
    await tester.pumpAndSettle();
    expect(find.text('WEB版'), findsOneWidget);
  });

  testWidgets('friend without internal permission defaults to ready public channel', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AppReferralPage(
      repository: PublicOnlyChannelRepository(), friendInvite: true,
    )));
    await tester.pumpAndSettle();
    expect(find.text('公開版の案内'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '送信')).onPressed, isNotNull);
  });
}

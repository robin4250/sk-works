import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat exposes all friends site groups partner tabs', () {
    final page = File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();

    for (final key in [
      '_ChatTab.all',
      '_ChatTab.friends',
      '_ChatTab.site',
      '_ChatTab.groups',
      '_ChatTab.partner',
    ]) {
      expect(page, contains(key));
    }
    expect(page, isNot(contains('_ChatTab.direct')));
    expect(page, contains("'友達一覧'"));
  });

  test('friend picker starts direct chat from a vertical friend list', () {
    final page = File('lib/features/chat/chat_friends_page.dart').readAsStringSync();
    final chat = File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();

    expect(page, contains('selectForChat'));
    expect(page, contains('ListView.separated'));
    expect(chat, contains('_openFriendsForChat'));
    expect(chat, contains('_startDirect(friend)'));
  });

  test('custom group workspace supports create invite accept leave and removal', () {
    final page = File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();
    final repo =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();

    expect(page, contains("'グループチャット作成'"));
    expect(page, contains("'友達を招待'"));
    expect(page, contains("'友達招待'"));
    expect(page, contains("'脱退'"));
    expect(page, contains("'長押しで追放'"));
    expect(repo, contains("'create_custom_chat_group'"));
    expect(repo, contains("'invite_friend_to_chat_group'"));
    expect(repo, contains("'respond_chat_group_invite'"));
    expect(repo, contains("'leave_custom_chat_group'"));
    expect(repo, contains("'remove_custom_chat_group_member'"));
  });

  test('custom group list exposes swipe pin hide delete and sound controls', () {
    final page = File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();

    expect(page, contains('Dismissible('));
    expect(page, contains("'上位にピン留め'"));
    expect(page, contains("'非表示'"));
    expect(page, contains("'削除'"));
    expect(page, contains("'通知音をOFF'"));
    expect(page, contains("'notifications_active_outlined'"));
  });

  test('settings exposes app notification sound switch', () {
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();

    expect(settings, contains("'アプリの通知音設定'"));
    expect(settings, contains("'sko_app_notification_sound_enabled'"));
    expect(settings, contains('_appNotificationSoundEnabled'));
  });

  test('production migration mirror protects participant-only group workflow', () {
    final migration = File(
      'supabase/migrations/20261004155625_add_custom_chat_group_membership_workflow.sql',
    ).readAsStringSync();

    expect(migration, contains('participants_only'));
    expect(migration, contains('private.chat_group_invites'));
    expect(migration, contains('private.sko_friends'));
    expect(migration, contains("'chat_group_invite'"));
    expect(migration, contains('if v_remaining=0 then'));
    expect(migration, contains('revoke execute on function public.'));
    expect(migration, contains('grant execute on function public.'));
  });
}

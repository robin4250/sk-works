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
    expect(page, contains('Icons.notifications_active_outlined'));
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

  test('cross-company friends use explicit participant access', () {
    final repository =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/20261004161045_allow_cross_company_custom_chat_members.sql',
    ).readAsStringSync();

    expect(repository, contains('participants_only, created_by'));
    expect(repository, contains("'custom_chat_group_members'"));
    expect(migration, contains('if v_participants_only then'));
    expect(
      migration,
      contains('where cgm.group_id=p_group_id'),
    );
    expect(migration, contains('custom_chat_group_members'));
    expect(
      migration,
      contains(
        'revoke execute on function public.custom_chat_group_members(uuid) from public, anon',
      ),
    );
  });


  test('conversations stay inside friends and groups tabs', () {
    final page =
        File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();

    expect(page, contains("'direct' => _ChatTab.friends"));
    expect(page, contains('if (_isCustomGroup(group)) return _ChatTab.groups'));
    expect(
      page,
      contains('_ChatTab.groups => _selectedGroupId != null'),
    );
    expect(page, contains("'友達を招待'"));
  });


  test('cross-company direct chats use friend display names', () {
    final page =
        File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();
    final repository =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();

    expect(repository, contains('friendByUser'));
    expect(page, contains("'direct_other_user_id'"));
    expect(
      repository,
      contains(".from('communication_group_members')"),
    );
    expect(
      repository,
      contains(
        "final directMembershipRows = await _client\n"
        "        .from('communication_group_members')\n"
        "        .select('group_id, user_id');",
      ),
    );
  });


  test('custom group members can remove another member but not self', () {
    final migration = File(
      'supabase/migrations/20261004162159_allow_custom_chat_members_to_remove_members.sql',
    ).readAsStringSync();

    expect(migration, contains('and me.user_id=v_user'));
    expect(
      migration,
      contains('自分の脱退は脱退ボタンを使用してください'),
    );
    expect(
      migration,
      contains('delete from public.communication_group_members'),
    );
  });

}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('site lifecycle creates one site chat and joins attendance users', () {
    final sql = File(
      'supabase/migrations/20260930060000_connect_site_chat_lifecycle.sql',
    ).readAsStringSync();

    expect(sql, contains('one_site_chat_per_site'));
    expect(sql, contains('sync_site_chat_lifecycle'));
    expect(sql, contains('attendance_join_site_chat'));
    expect(sql, contains('verification_join_site_chat'));
    expect(sql, contains("new.event_type='clock_in'"));
    expect(sql, contains('on conflict (group_id,user_id) do nothing'));
    expect(sql, contains('participants_only=true'));
  });

  test('site chat managers can enter without attendance and archived chats cannot send', () {
    final sql = File(
      'supabase/migrations/20260930060000_connect_site_chat_lifecycle.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains("v_group_type='site'\n     and v_role in ('owner','admin','manager')"),
    );
    expect(sql, contains('g.archived_at is null'));
    expect(sql, contains("when s.status='completed'"));
  });

  test('site completion UI confirms and soft-completes instead of deleting', () {
    final page = File('lib/features/sites/site_cloud_page.dart').readAsStringSync();
    final repository =
        File('lib/features/sites/site_cloud_repository.dart').readAsStringSync();

    expect(page, contains('現場終了の確認'));
    expect(page, contains('チャットは削除せず、履歴を残したままアーカイブします'));
    expect(page, isNot(contains('await repository.delete(site.id)')));
    expect(repository, contains("update({\n      'status': 'completed'"));
    expect(repository, isNot(contains(".from('sites').delete()")));
  });

  test('archived site chat is read-only in chat UI', () {
    final repository =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();
    final page = File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();

    expect(repository, contains('archived_at'));
    expect(page, contains('アーカイブ済み'));
    expect(page, contains('_sending || archived ? null : _send'));
    expect(page, contains('_sending || archived ? null : _showAttachMenu'));
  });
}

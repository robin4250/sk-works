import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat restore covers attachments safety friends and unread contracts', () {
    final page =
        File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();
    final repository =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();
    final friends =
        File('lib/features/chat/chat_friends_page.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/20261001212639_add_sko_friend_id_foundation.sql',
    ).readAsStringSync();

    expect(page, contains("'カメラ'"));
    expect(page, contains('ImageSource.camera'));
    expect(page, contains("'メッセージを削除しますか？'"));
    expect(page, contains("'ブロック解除'"));
    expect(page, contains('Badge('));
    expect(page, contains("sko_chat_last_read_"));
    expect(page, contains("'友達追加'"));
    expect(repository, contains("rpc('chat_block_list')"));
    expect(repository, contains("'set_chat_block'"));
    expect(repository, contains("'sko_friend_workspace'"));
    expect(repository, contains("'search_personal_sko_id'"));
    expect(friends, contains("'SKO ID検索'"));
    expect(friends, contains("'届いた申請'"));
    expect(friends, contains("'友達一覧'"));
    expect(migration, contains('private.personal_sko_ids'));
    expect(migration, contains('private.sko_friend_requests'));
    expect(migration, contains('private.sko_friends'));
    expect(migration, contains('grant execute'));
  });
}

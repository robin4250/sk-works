import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selected chat exposes participant list from group membership', () {
    final page =
        File('lib/features/chat/chat_cloud_page.dart').readAsStringSync();
    final repository =
        File('lib/features/chat/chat_cloud_repository.dart').readAsStringSync();

    expect(page, contains('_showSelectedGroupMembers'));
    expect(page, contains('参加メンバー'));
    expect(page, contains('loadGroupMembers(groupId)'));
    expect(page, contains('onTap: _showSelectedGroupMembers'));

    expect(repository, contains('loadGroupMembers(String groupId)'));
    expect(repository, contains("from('communication_group_members')"));
    expect(repository, contains("rpc('company_member_profiles')"));
  });
}

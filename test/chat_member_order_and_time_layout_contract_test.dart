import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('chat header member list is ordered by recent chat activity', () {
    final repository = read('lib/features/chat/chat_cloud_repository.dart');
    final page = read('lib/features/chat/chat_cloud_page.dart');

    expect(repository, contains("'last_message_at': lastMessageByUser[userId]"));
    expect(repository, contains('final byRecent = bDate.compareTo(aDate)'));
    expect(repository, contains("'company_name': companyName"));
    expect(page, contains("member['company_name']"));
    expect(page, contains('onTap: _showSelectedGroupMembers'));
  });

  test('chat opens on the all-conversations list without auto-selecting', () {
    final page = read('lib/features/chat/chat_cloud_page.dart');

    expect(
      page,
      contains("final next = groups.any((g) => g['id']?.toString() == previous)"),
    );
    expect(page, contains(': null;'));
    expect(page, contains('List<Map<String, dynamic>> get _allGroups'));
    expect(page, contains("_ChatTab.all => _selectedGroupId == null"));
    expect(page, isNot(contains("groups.first['id']?.toString()")));
  });

  test('message time is outside the bubble like LINE', () {
    final page = read('lib/features/chat/chat_cloud_page.dart');

    expect(page, contains('final timeWidget = Padding('));
    expect(page, contains('children: own'));
    expect(page, contains('timeWidget,'));
    expect(page, contains('bubble,'));
    expect(
      page,
      isNot(contains("alignment: Alignment.bottomRight")),
    );
  });
}

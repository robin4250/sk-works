import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_list_widgets.dart';

void main() {
  test('tab totals deduplicate groups and ignore zero counts', () {
    expect(chatUnreadTotal([{'id':'a'},{'id':'a'},{'id':'b'},{'id':'c'}], {'a':120,'b':3,'c':0}),123);
  });
  testWidgets('row keeps two-line preview and right hand unread at small width', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width:320,
      child: ChatConversationTile(name:'長いグループ名 長いグループ名',
      preview:'最新メッセージの内容\n二行目\n三行目は省略',time:'10/13',
      unreadCount:120,icon:Icons.groups_outlined,onTap:()=>tapped=true)))));
    expect(tester.takeException(),isNull);
    final preview=tester.widget<Text>(find.text('最新メッセージの内容\n二行目\n三行目は省略'));
    expect(preview.maxLines,2);expect(preview.overflow,TextOverflow.ellipsis);
    expect(tester.getTopLeft(find.text('10/13')).dx,greaterThan(tester.getTopLeft(find.text('長いグループ名 長いグループ名')).dx));
    await tester.tap(find.text('長いグループ名 長いグループ名'));expect(tapped,true);
  });
  testWidgets('read clears number badge and missing photo keeps normal icon', (tester) async {
    Future<void> show(int count) => tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatConversationTile(
      name:'グループ',preview:'本文',time:'10:24',unreadCount:count,
      icon:Icons.groups_outlined,onTap:(){}))));
    await show(2);expect(find.text('2'),findsOneWidget);
    await show(0);expect(find.text('2'),findsNothing);expect(find.byIcon(Icons.groups_outlined),findsOneWidget);
  });
}

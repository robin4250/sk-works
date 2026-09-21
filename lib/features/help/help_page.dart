import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'manual_content.dart';
import 'manual_library_page.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({
    super.key,
    required this.role,
  });

  final ManualRole role;

  @override
  Widget build(BuildContext context) {
    final roleLabel = ManualContent.roleLabel(role);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ヘルプ',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$roleLabel用の使い方',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ボタンの場所、操作手順、サポートが出るタイミングまで説明します。'
                      'A4 PDFで印刷・共有もできます。',
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ManualLibraryPage(role: role),
                        ),
                      ),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('使い方・説明書を開く'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const _HelpTile(
              icon: Icons.login_outlined,
              title: '出勤・退勤',
              body: '一般ユーザー・サブ管理者・管理者の全員が自分自身の出勤・退勤を登録できます。位置情報は操作時だけ取得します。',
            ),
            const SizedBox(height: 10),
            const _HelpTile(
              icon: Icons.calendar_month_outlined,
              title: '出勤表',
              body: '週単位で現場・出勤時刻・残業・早出・手当を確認できます。月間カレンダーからA4プレビューも確認できます。',
            ),
            const SizedBox(height: 10),
            const _HelpTile(
              icon: Icons.description_outlined,
              title: '日報',
              body: '朝の出勤データから現場とメンバーを自動表示します。責任者サイン後は確定となり、修正には会社で設定された承認担当者の承認が必要です。',
            ),
            const SizedBox(height: 10),
            const _HelpTile(
              icon: Icons.chat_bubble_outline,
              title: 'チャット',
              body: '現場や個別の連絡を確認します。重要な通知は右上のベルからいつでも確認できます。',
            ),
            const SizedBox(height: 10),
            _HelpTile(
              icon: Icons.lock_person_outlined,
              title: '第2認証',
              body: switch (role) {
                ManualRole.admin =>
                  '管理者は請求書と管理者用現場データを開く時に第2パスワードを使用します。',
                _ =>
                  '一般ユーザーとサブ管理者は給与明細を開く時に第2パスワードを使用します。',
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  const _HelpTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

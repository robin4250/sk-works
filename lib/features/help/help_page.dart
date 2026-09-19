import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
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
          children: const [
            _HelpTile(
              icon: Icons.login_outlined,
              title: '出勤・退勤',
              body: 'ホームから現場を確認して、出勤・退勤を登録します。会社設定により位置情報や写真を使う場合があります。',
            ),
            SizedBox(height: 10),
            _HelpTile(
              icon: Icons.calendar_month_outlined,
              title: '出勤表',
              body: '週単位で現場・出勤時刻・残業・早出・手当を確認できます。月間カレンダーからA4プレビューも確認できます。',
            ),
            SizedBox(height: 10),
            _HelpTile(
              icon: Icons.description_outlined,
              title: '日報',
              body: '朝の出勤データから現場とメンバーを自動表示します。責任者サイン後は確定となり、修正には承認が必要です。',
            ),
            SizedBox(height: 10),
            _HelpTile(
              icon: Icons.chat_bubble_outline,
              title: 'チャット',
              body: '現場や個別の連絡を確認します。重要な通知は右上のベルからいつでも確認できます。',
            ),
            SizedBox(height: 10),
            _HelpTile(
              icon: Icons.lock_person_outlined,
              title: '重要情報の保護',
              body: '請求書や管理者用データは、通常ログインとは別の第2パスワードで保護されます。',
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

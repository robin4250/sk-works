import 'package:flutter/material.dart';

void main() {
  runApp(const SkWorksApp());
}

class SkWorksApp extends StatelessWidget {
  const SkWorksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SK WORKS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F4E78)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const _menuItems = <({IconData icon, String title, String subtitle})>[
    (icon: Icons.people_alt_outlined, title: '社員・協力会社', subtitle: '社員・下請け会社・作業員を管理'),
    (icon: Icons.badge_outlined, title: '資格管理', subtitle: '資格マスターと保有資格を管理'),
    (icon: Icons.apartment_outlined, title: '現場管理', subtitle: '現場情報・担当者・進捗を管理'),
    (icon: Icons.schedule_outlined, title: '勤怠・人工', subtitle: '出面・人工・残業などを記録'),
    (icon: Icons.receipt_long_outlined, title: '請求管理', subtitle: '得意先・現場別の請求を管理'),
    (icon: Icons.settings_outlined, title: '設定', subtitle: '会社情報・各種マスターを設定'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SK WORKS'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SK WORKS',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text('会社・現場・人員・資格・請求をまとめて管理する業務アプリ'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ..._menuItems.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(item.icon),
                  title: Text(item.title),
                  subtitle: Text(item.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${item.title} は次の開発段階で実装します')),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

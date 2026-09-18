import 'package:flutter/material.dart';

import 'app.dart' as legacy;
import 'branding/product_brand.dart';
import 'data/supabase_backend.dart';
import 'features/albums/albums_cloud_page.dart';
import 'features/attendance/attendance_cloud_page.dart';
import 'features/attendance/attendance_page.dart';
import 'features/attendance/attendance_verification_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/chat/chat_cloud_page.dart';
import 'features/invoices/invoice_cloud_page.dart';
import 'features/invoices/invoice_page.dart';
import 'features/notes/notes_cloud_page.dart';
import 'features/people/people_cloud_page.dart';
import 'features/people/people_page.dart';
import 'features/qualifications/qualification_cloud_page.dart';
import 'features/qualifications/qualification_page.dart';
import 'features/settings/settings_page.dart';
import 'features/sites/site_cloud_page.dart';
import 'features/sites/site_page.dart';

class SkWorksApp extends StatelessWidget {
  const SkWorksApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF173B57);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: ProductBrand.displayName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: SupabaseBackend.isInitialized
          ? SupabaseAuthGate(
              homeBuilder: (onSignOut) => HomePage(onSignOut: onSignOut),
            )
          : const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  Widget _pageFor(legacy.ModuleDefinition module) {
    return switch (module.storageKey) {
      'people' => SupabaseBackend.isInitialized
          ? const PeopleCloudPage()
          : const PeoplePage(),
      'qualifications' => SupabaseBackend.isInitialized
          ? const QualificationCloudPage()
          : const QualificationPage(),
      'sites' => SupabaseBackend.isInitialized
          ? const SiteCloudPage()
          : const SitePage(),
      'attendance' => SupabaseBackend.isInitialized
          ? const AttendanceCloudPage()
          : const AttendancePage(),
      'invoices' => SupabaseBackend.isInitialized
          ? const InvoiceCloudPage()
          : const InvoicePage(),
      'settings' => const SettingsPage(),
      _ => legacy.ModulePage(module: module),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(ProductBrand.displayName),
        actions: [
          if (onSignOut != null)
            IconButton(
              tooltip: 'ログアウト',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ProductBrand.displayName,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text(ProductBrand.tagline),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '業務メニュー',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            for (final module in legacy.HomePage.modules)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(module.icon)),
                    title: Text(
                      module.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(module.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _pageFor(module)),
                    ),
                  ),
                ),
              ),
            if (SupabaseBackend.isInitialized) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.how_to_reg_outlined),
                    ),
                    title: const Text(
                      '出勤・退勤確認',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('手動 / 位置情報 / 位置情報＋写真で勤務を確認'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AttendanceVerificationPage()),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.chat_bubble_outline),
                    ),
                    title: const Text(
                      'チャット',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('グループ・現場ごとの連絡をリアルタイムで共有'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChatCloudPage()),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.sticky_note_2_outlined),
                    ),
                    title: const Text(
                      'ノート',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('グループ・現場ごとの連絡事項や引継ぎを管理'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NotesCloudPage()),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.photo_album_outlined),
                    ),
                    title: const Text(
                      'アルバム',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('グループ・現場ごとの写真をアルバムで管理'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AlbumsCloudPage()),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

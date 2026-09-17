import 'package:flutter/material.dart';

import 'app.dart' as legacy;
import 'data/supabase_backend.dart';
import 'features/attendance/attendance_cloud_page.dart';
import 'features/attendance/attendance_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/invoices/invoice_cloud_page.dart';
import 'features/invoices/invoice_page.dart';
import 'features/people/people_cloud_page.dart';
import 'features/people/people_page.dart';
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
      title: 'SK WORKS',
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
      'qualifications' => const QualificationPage(),
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
        title: const Text('SK WORKS'),
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
                      'SK WORKS',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    const Text('会社・現場・人員・資格・勤怠・請求をひとつに。'),
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
          ],
        ),
      ),
    );
  }
}

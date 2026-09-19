import 'package:flutter/material.dart';

import 'app.dart' as legacy;
import 'branding/product_brand.dart';
import 'data/supabase_backend.dart';
import 'features/albums/albums_cloud_page.dart';
import 'features/attendance/attendance_cloud_page.dart';
import 'features/attendance/attendance_page.dart';
import 'features/attendance/attendance_verification_page.dart';
import 'features/attendance/worker_attendance_sheet_page.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/secondary_protected_page.dart';
import 'features/chat/chat_cloud_page.dart';
import 'features/chat/line_history_preview_page.dart';
import 'features/chat/today_line_attendance_page.dart';
import 'features/home/friendly_home_content.dart';
import 'features/home/home_membership_repository.dart';
import 'features/invoices/invoice_cloud_page.dart';
import 'features/invoices/invoice_page.dart';
import 'features/notes/notes_cloud_page.dart';
import 'features/people/people_cloud_page.dart';
import 'features/people/people_page.dart';
import 'features/people/worker_document_page.dart';
import 'features/qualifications/qualification_certificate_page.dart';
import 'features/qualifications/qualification_cloud_page.dart';
import 'features/qualifications/qualification_page.dart';
import 'features/settings/company_module_settings_repository.dart';
import 'features/settings/rollout_readiness_page.dart';
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
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
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

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _moduleSettingsRepository =
      CompanyModuleSettingsRepository.maybeCreate();
  final _membershipRepository = HomeMembershipRepository.maybeCreate();

  Map<String, bool> _moduleStates = const {};
  String _role = SupabaseBackend.isInitialized ? 'viewer' : 'owner';

  bool get _isAdmin =>
      _role == 'owner' || _role == 'admin' || _role == 'manager';

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    await Future.wait([
      _loadModuleSettings(),
      _loadRole(),
    ]);
  }

  Future<void> _loadRole() async {
    final repository = _membershipRepository;
    if (repository == null) return;
    try {
      final role = await repository.loadRole();
      if (!mounted) return;
      setState(() => _role = role);
    } catch (_) {
      // Default to the worker-safe view if role loading fails.
    }
  }

  Future<void> _loadModuleSettings() async {
    final repository = _moduleSettingsRepository;
    if (repository == null) return;
    try {
      final states = await repository.loadOptionalModuleStates();
      if (!mounted) return;
      setState(() => _moduleStates = states);
    } catch (_) {
      // Keep modules visible if settings cannot be loaded.
    }
  }

  bool _moduleEnabled(String key) {
    if (!SupabaseBackend.isInitialized) return true;
    if (key == 'people' || key == 'settings') return true;
    return _moduleStates[key] ?? true;
  }

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
          ? (_isAdmin
              ? const AttendanceCloudPage()
              : const WorkerAttendanceSheetPage())
          : const AttendancePage(),
      'invoices' => SupabaseBackend.isInitialized
          ? const SecondaryProtectedPage(
              title: '請求書',
              child: InvoiceCloudPage(),
            )
          : const InvoicePage(),
      'settings' => const SettingsPage(),
      _ => legacy.ModulePage(module: module),
    };
  }

  Future<void> _openHomeAction(String key) async {
    Widget? page;

    switch (key) {
      case 'attendance_verify':
        page = const AttendanceVerificationPage();
        break;
      case 'qualification_certificates':
        page = const QualificationCertificatePage();
        break;
      case 'documents':
        page = const WorkerDocumentPage();
        break;
      case 'chat':
        page = const ChatCloudPage();
        break;
      case 'today_line':
        page = const TodayLineAttendancePage();
        break;
      case 'line_history':
        page = const LineHistoryPreviewPage();
        break;
      case 'rollout':
        page = const RolloutReadinessPage();
        break;
      case 'notes':
        page = const NotesCloudPage();
        break;
      case 'albums':
        page = const AlbumsCloudPage();
        break;
      case 'settings':
        page = const SettingsPage();
        break;
      default:
        for (final module in legacy.HomePage.modules) {
          if (module.storageKey == key) {
            page = _pageFor(module);
            break;
          }
        }
    }

    if (page == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page!),
    );

    if (key == 'settings') {
      await _loadModuleSettings();
    }
  }

  void _showNotificationsPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('共通通知センターをこのベルに接続する工程を続けています'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          ProductBrand.displayName,
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'お知らせ',
            onPressed: _showNotificationsPlaceholder,
            icon: const Badge(
              isLabelVisible: false,
              child: Icon(Icons.notifications_outlined),
            ),
          ),
          if (widget.onSignOut != null)
            IconButton(
              tooltip: 'ログアウト',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      floatingActionButton:
          SupabaseBackend.isInitialized && _moduleEnabled('chat')
              ? FloatingActionButton.extended(
                  onPressed: () => _openHomeAction('chat'),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text(
                    'チャット',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : null,
      body: SafeArea(
        child: FriendlyHomeContent(
          role: _role,
          moduleEnabled: _moduleEnabled,
          onOpen: _openHomeAction,
          onRefresh: _loadHomeData,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../notifications/notification_bell.dart';
import 'manual_content.dart';
import 'menu_help_catalog.dart';
import 'manual_library_page.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({
    super.key,
    required this.role,
    this.visibleFeatureKeys,
  });

  final ManualRole role;
  final Set<String>? visibleFeatureKeys;

  @override
  Widget build(BuildContext context) {
    final roleLabel = ManualContent.roleLabel(role);
    final helpItems = MenuHelpCatalog.visibleFor(
      role: role,
      visibleKeys: visibleFeatureKeys,
    );

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
            for (final item in helpItems) ...[
              _HelpTile(
                icon: _iconFor(item.key),
                title: item.label,
                body: item.purpose,
                destination: item.destination,
                access: item.access,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
  IconData _iconFor(String key) => switch (key) {
        'attendance' => Icons.calendar_month_outlined,
        'daily_report' => Icons.description_outlined,
        'chat' => Icons.chat_bubble_outline,
        'site_register' || 'admin_sites' => Icons.business_outlined,
        'people' || 'employee_register' => Icons.groups_2_outlined,
        'payroll' || 'payroll_settings' || 'payroll_adjustments' =>
          Icons.payments_outlined,
        'qualifications' => Icons.badge_outlined,
        'documents' || 'company_documents' => Icons.fact_check_outlined,
        'company_deliveries' => Icons.folder_shared_outlined,
        'invoices' => Icons.receipt_long_outlined,
        'vehicle_routes' => Icons.route_outlined,
        'profile' => Icons.account_circle_outlined,
        'notes' => Icons.sticky_note_2_outlined,
        'albums' => Icons.photo_album_outlined,
        'approvals' || 'employee_onboarding_approvals' =>
          Icons.approval_outlined,
        'today_line' => Icons.today_outlined,
        'settings' => Icons.settings_outlined,
        _ => Icons.help_outline,
      };

}

class _HelpTile extends StatelessWidget {
  const _HelpTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.destination,
    required this.access,
  });

  final IconData icon;
  final String title;
  final String body;
  final String destination;
  final String access;

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
                  const SizedBox(height: 8),
                  Text(
                    destination,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '利用権限：$access',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

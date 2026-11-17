import 'package:flutter/material.dart';

import 'app_v2.dart';
import 'features/companies/company_invitation_tab.dart';
import 'features/companies/trade_company_invitation_page.dart';
import 'branding/sko_theme.dart';
import 'data/supabase_backend.dart';
import 'international/language_controller.dart';
import 'widgets/sko_orientation_policy.dart';

export 'app_v2.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SkoOrientationPolicy.initialize(WidgetsBinding.instance.platformDispatcher.implicitView);
  try {
    await SkoThemeController.load();
  } catch (_) {
    // Keep the default SKO palette if local preferences cannot be read.
  }
  try {
    await SkoLanguageController.loadLocal();
  } catch (_) {
    // Keep Japanese as the safe default if local language state cannot be read.
  }
  try {
    await SupabaseBackend.initializeIfConfigured();
  } catch (_) {
    // Fail closed in the app UI instead of terminating before runApp.
  }
  final uri = Uri.base;
  final invitation = readTradeCompanyInvitation(uri);
  if (invitation != null) writeCompanyInvitationTab(uri.fragment);
  final pendingInvitation = invitation ?? readTradeCompanyInvitation(
    uri.replace(fragment: readCompanyInvitationTab() ?? ''),
  );
  runApp(SkWorksApp(companyInvitation: pendingInvitation));
}

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'personal_vault_page.dart';
import 'personal_vault_repository.dart';

/// Candidate route. Root must expose it only after API/Storage deployment tests.
class PersonalVaultScreen extends StatelessWidget {
  const PersonalVaultScreen({super.key,required this.client});
  final SupabaseClient client;
  @override
  Widget build(BuildContext context) {
    final repository = PersonalVaultRepository(client);
    return PersonalVaultPage(loadMine: repository.loadMine,
      openOwnPdf: (entry, action) async {
        final bytes = await repository.downloadMine(entry);
        if (!context.mounted) { return; }
        switch (action) {
          case PersonalVaultAction.preview:
            await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) =>
              Scaffold(appBar: AppBar(title: Text(entry.label)),
                body: PdfPreview(build: (_) async => bytes, allowPrinting: false, allowSharing: false))));
          case PersonalVaultAction.save:
            await Printing.sharePdf(bytes: bytes, filename: 'SKO-personal-record.pdf');
          case PersonalVaultAction.print:
            await Printing.layoutPdf(onLayout: (_) async => bytes);
        }
      });
  }
}

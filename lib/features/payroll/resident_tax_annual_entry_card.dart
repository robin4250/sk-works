import 'package:flutter/material.dart';

/// Uses the existing annual editor; this card has no independent persistence.
class ResidentTaxAnnualEntryCard extends StatelessWidget {
  const ResidentTaxAnnualEntryCard({super.key, required this.onOpen});
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Card(child: ListTile(
    key: const ValueKey('resident-tax-annual-entry'),
    leading: const Icon(Icons.people_outline),
    title: const Text('住民税一括入力'),
    subtitle: const Text('全員の住民税を更新'),
    trailing: const Icon(Icons.chevron_right),
    onTap: onOpen,
  ));
}

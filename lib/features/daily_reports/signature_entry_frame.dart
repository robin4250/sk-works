import 'package:flutter/material.dart';

/// The parent signing action owns authorization and persistence.
class SignatureEntryFrame extends StatelessWidget {
  const SignatureEntryFrame({super.key, required this.role, required this.signerName});
  final String role;
  final String signerName;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('signature-entry-frame-$role'),
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.primary),
      borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('$role：$signerName', style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Text('横向きでサインしてください', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 8),
      const Text('タップして全画面でサイン', textAlign: TextAlign.center),
    ]));
}

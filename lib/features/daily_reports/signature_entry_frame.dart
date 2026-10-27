import 'package:flutter/material.dart';

/// The parent signing action owns authorization and persistence.
class SignatureEntryFrame extends StatelessWidget {
  const SignatureEntryFrame({super.key, required this.role, required this.signerName});
  final String role;
  final String signerName;

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return Semantics(
    button: true,
    child: Container(
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
      SizedBox(
        height: portrait ? 210 : 100,
        child: Center(child: FittedBox(fit: BoxFit.scaleDown,
          child: RotatedBox(
            key: const ValueKey('signature-entry-turn-guide'),
            quarterTurns: portrait ? 1 : 0,
            child: SizedBox(width: 210,
              child: Text('横向きでサインしてください', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary))),
          ))),
      ),
      const SizedBox(height: 8),
      const Text('タップして全画面でサイン', textAlign: TextAlign.center),
    ])));
  }
}

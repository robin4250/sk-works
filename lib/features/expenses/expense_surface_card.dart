import 'package:flutter/material.dart';

/// Expense surfaces follow the registration cards without sharing their data model.
class ExpenseSurfaceCard extends StatelessWidget {
  const ExpenseSurfaceCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: EdgeInsets.zero,
    elevation: 1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .12)),
    ),
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
}

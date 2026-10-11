import 'package:flutter/material.dart';

import '../../international/language_controller.dart';

class RelatedActionFooter extends StatelessWidget {
  const RelatedActionFooter({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(SkoLanguageController.tr(label)),
      ),
    ),
  );
}

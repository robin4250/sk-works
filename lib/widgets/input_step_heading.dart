import 'package:flutter/material.dart';

/// A visible sequence cue; the original controls and their labels stay intact.
class InputStepHeading extends StatelessWidget {
  const InputStepHeading({super.key, required this.number, required this.title,
    this.status, this.complete = false});
  final String number, title;
  final String? status;
  final bool complete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Row(children: [
      Text(number, style: TextStyle(color: Theme.of(context).colorScheme.primary,
        fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
      if (status != null) ...[
        const SizedBox(width: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (complete) ...[
            Icon(Icons.check_circle, size: 14, color: Colors.green.shade800),
            const SizedBox(width: 3),
          ],
          Text(status!, style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: complete ? Colors.green.shade800 : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600)),
        ]),
      ],
    ]));
}


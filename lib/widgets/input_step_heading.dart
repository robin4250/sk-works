import 'package:flutter/material.dart';

/// A visible sequence cue; the original controls and their labels stay intact.
class InputStepHeading extends StatelessWidget {
  const InputStepHeading({super.key, required this.number, required this.title});
  final String number, title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Row(children: [
      Text(number, style: TextStyle(color: Theme.of(context).colorScheme.primary,
        fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(width: 8),
      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]));
}

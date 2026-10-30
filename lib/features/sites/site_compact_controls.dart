import 'dart:math' as math;

import 'package:flutter/material.dart';

// Keep two readable lines, filter controls and actions at one shared height.
// Respect the user's text size rather than clipping scaled text into 48 pixels.
double siteControlHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final actionLabel = TextPainter(
    text: const TextSpan(text: '現場マップ',
      style: TextStyle(fontSize: 14, height: 1.2)),
    textScaler: scaler,
    textDirection: Directionality.of(context),
  )..layout(maxWidth: math.max(1, (MediaQuery.sizeOf(context).width - 44) / 2 - 52));
  final height = math.max(48.0,
    math.max(scaler.scale(14) * 1.2 + scaler.scale(12) * 1.2 + 10,
      actionLabel.height + 16));
  actionLabel.dispose();
  return height;
}

class SiteCompactCard extends StatelessWidget {
  const SiteCompactCard({super.key, required this.height, required this.name,
    required this.details, required this.onTap});
  final double height;
  final String name;
  final String details;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const CircleAvatar(radius: 16,
              child: Icon(Icons.apartment_outlined, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Tooltip(
              message: '$name\n$details',
              child: Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.2,
                      fontWeight: FontWeight.w700)),
                  Text(details, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.2)),
                ]),
            )),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20),
          ]),
        ),
      ),
    ),
  );
}

class SiteCompactFilter extends StatelessWidget {
  const SiteCompactFilter({super.key, required this.height, required this.label,
    required this.selected, required this.onSelected});
  final double height;
  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ChoiceChip(
      label: label,
      labelStyle: const TextStyle(fontSize: 14, height: 1.2),
      selected: selected,
      onSelected: onSelected,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.symmetric(horizontal: 8,
        vertical: math.max(0, (height - MediaQuery.textScalerOf(context).scale(14) * 1.2 - 8) / 2)),
    ),
  );
}

class SiteCompactAction extends StatelessWidget {
  const SiteCompactAction({super.key, required this.height,
    required this.controlKey, required this.icon, required this.label,
    required this.onPressed});
  final double height;
  final String controlKey;
  final Widget icon;
  final Widget label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey(controlKey),
    height: height,
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 14, height: 1.2,
          fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      icon: icon,
      label: label,
    ),
  );
}

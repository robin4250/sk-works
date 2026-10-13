import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared geometry for attention and weather cards. Text scale changes both.
class HomeInformationCard extends StatelessWidget {
  const HomeInformationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.details,
    required this.onTap,
    this.trailing,
    this.footer,
    this.showChevron = true,
    this.detailsTrailing,
    this.leading,
    this.leadingAtTop = false,
    this.headerCenter,
    this.detailsContent,
  });
  final IconData icon;
  final String title;
  final String details;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? footer;
  final bool showChevron;
  final Widget? detailsTrailing;
  final Widget? leading;
  final bool leadingAtTop;
  final Widget? headerCenter;
  /// Optional compact content inside the existing information/footer bounds.
  final Widget? detailsContent;

  static ({double titleFont, double titleHeight, double height}) _layoutFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final titleFont = (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) * 1.25;
    final navigationHeight = (scale.scale(11) + scale.scale(10)) * 1.1 + 4;
    final titleHeight = math.max(48, math.max(scale.scale(titleFont) * 1.25, navigationHeight)).ceilToDouble();
    final detailsHeight = (scale.scale(11) * 1.25).ceilToDouble() * 3 + 2;
    return (titleFont: titleFont, titleHeight: titleHeight, height: titleHeight + detailsHeight + 24);
  }

  /// Shared frame height, including compact weather information and legal branding.
  static double heightFor(BuildContext context) => _layoutFor(context).height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context);
    final layout = _layoutFor(context);
    final titleFont = layout.titleFont;
    final titleHeight = layout.titleHeight;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: layout.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 50,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
                alignment: leadingAtTop ? Alignment.topCenter : Alignment.center,
                child: leadingAtTop ? Padding(padding: const EdgeInsets.only(top: 10), child: leading) : leading ?? Icon(icon, color: colors.onPrimary),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: titleHeight,
                        child: Row(
                          children: [
                            Expanded(
                              child: headerCenter ?? FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: titleFont,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                            if (trailing != null) trailing!,
                            if (headerCenter == null) const SizedBox(width: 4),
                            if (showChevron) const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (detailsContent != null)
                        SizedBox(height: layout.height - titleHeight - 24, child: detailsContent)
                      else if (detailsTrailing == null)
                        Text(
                          details,
                          maxLines: footer == null ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 11, height: 1.25),
                        )
                      else
                        SizedBox(
                          height: (scale.scale(11) * 1.25).ceilToDouble(),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  details,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontSize: 11, height: 1.25),
                                ),
                              ),
                              const SizedBox(width: 6),
                              detailsTrailing!,
                            ],
                          ),
                        ),
                      if (detailsContent == null && footer != null)
                        Text(
                          footer!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 10.5, height: 1.25),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

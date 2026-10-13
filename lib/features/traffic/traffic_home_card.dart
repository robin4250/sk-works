import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../international/language_controller.dart';
import 'traffic_link_policy.dart';
import 'traffic_destination_icon.dart';
import 'traffic_personal_shortcut.dart';
import 'traffic_shortcut_store.dart';

typedef TrafficLinkLauncher = Future<bool> Function(Uri uri);

/// Four fixed slots; disabled destinations remain in their original slots.
class TrafficHomeCard extends StatefulWidget {
  const TrafficHomeCard({
    super.key,
    required this.availability,
    this.launcher,
    this.shortcutScope,
  });

  final TrafficAvailability availability;
  final TrafficLinkLauncher? launcher;
  final TrafficShortcutScope? shortcutScope;

  @override
  State<TrafficHomeCard> createState() => _TrafficHomeCardState();
}

class _TrafficHomeCardState extends State<TrafficHomeCard> {
  bool _opening = false;

  Future<void> _open(TrafficDestination destination) async {
    if (_opening || !widget.availability.permits(destination)) {
      return;
    }
    setState(() => _opening = true);
    var opened = false;
    try {
      final uri = trafficDestinationUri(destination);
      opened = await (widget.launcher?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      opened = false;
    }
    if (!mounted) {
      return;
    }
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SkoLanguageController.tr('外部サービスを開けませんでした。もう一度お試しください。'))),
      );
    }
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SkoLanguageController.tr('交通案内')),
        content: Text(SkoLanguageController.tr('最寄駅・バス停はGoogleマップ、電車乗換はYahoo!乗換案内を開きます。現在地の確認や検索は外部サービス側で行います。4枠目の「追加」で、この端末から開ける対応アプリやWebサイトを1件登録できます。交通カード本体を長押しすると並べ替えできます。登録した項目を長押しすると編集・解除できます。設定はこの端末の自分のアカウント・会社別に保存します。端末の全アプリを一覧表示する機能ではありません。')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(SkoLanguageController.tr('閉じる')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final colors = Theme.of(context).colorScheme;
    final labels = ['最寄駅', '電車乗換', 'バス停'];
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // Give all four destinations the width previously reserved for a handle.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(children: [
          for (var index = 0; index < 3; index++)
            Expanded(
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TextButton(
                key: ValueKey('traffic-${TrafficDestination.values[index].name}'),
                onPressed: widget.availability.permits(TrafficDestination.values[index]) && !_opening
                    ? () => _open(TrafficDestination.values[index])
                    : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: colors.primaryContainer.withValues(alpha: 0.55),
                  disabledBackgroundColor: colors.surfaceContainerHighest,
                  side: BorderSide(color: colors.outlineVariant),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(children: [
                  TrafficDestinationIcon(
                    key: ValueKey('traffic-icon-${TrafficDestination.values[index].name}'),
                    destination: TrafficDestination.values[index],
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      SkoLanguageController.tr(labels[index]),
                      maxLines: 1, softWrap: false,
                      style: const TextStyle(fontSize: 10, height: 1.15),
                    ),
                  )),
                ]),
              ),
              ),
            ),
          Expanded(child: TrafficPersonalShortcut(
            key: const ValueKey('traffic-future-slot'),
            scope: widget.shortcutScope,
          )),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: SkoLanguageController.tr('交通案内のヘルプ'),
              onPressed: _help,
              iconSize: 18,
              icon: const Icon(Icons.help_outline),
            ),
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../international/language_controller.dart';
import 'traffic_destination_icon.dart';
import 'traffic_link_policy.dart';
import 'traffic_personal_shortcut.dart';
import 'traffic_route_repository.dart';
import 'traffic_shortcut_store.dart';

typedef TrafficLinkLauncher = Future<bool> Function(Uri uri);

class TrafficHomeCard extends StatefulWidget {
  const TrafficHomeCard({
    super.key,
    required this.availability,
    this.launcher,
    this.shortcutScope,
    this.canEditShortcuts = false,
    this.routeLoader,
  });

  static const buttonHeight = trafficButtonHeight;
  final TrafficAvailability availability;
  final TrafficLinkLauncher? launcher;
  final TrafficShortcutScope? shortcutScope;
  final bool canEditShortcuts;
  final TrafficRouteLoader? routeLoader;

  @override
  State<TrafficHomeCard> createState() => _TrafficHomeCardState();
}

class _TrafficHomeCardState extends State<TrafficHomeCard> {
  bool _opening = false;

  Future<void> _open(
    Future<Uri> Function() resolve, {
    bool sameTab = false,
  }) async {
    if (_opening) return;
    final scope = widget.shortcutScope;
    setState(() => _opening = true);
    String? message;
    try {
      final uri = await resolve();
      if (!mounted || scope != widget.shortcutScope) return;
      final opened =
          await (widget.launcher?.call(uri) ??
              launchUrl(
                uri,
                mode: kIsWeb && sameTab
                    ? LaunchMode.platformDefault
                    : LaunchMode.externalApplication,
                webOnlyWindowName: kIsWeb && sameTab ? '_self' : null,
              ));
      if (!opened) message = '外部サービスを開けませんでした。もう一度お試しください。';
    } on TrafficRouteException catch (error) {
      message = switch (error.problem) {
        TrafficRouteProblem.addressMissing =>
          '住所が登録されていません。プロフィールまたは会社情報の住所を確認してください。',
        TrafficRouteProblem.permissionDenied =>
          '位置情報の利用を許可してください。端末またはブラウザの設定を確認できます。',
        TrafficRouteProblem.locationOff => '端末の位置情報サービスをオンにしてください。',
      };
    } catch (_) {
      message = '住所または現在地を確認できませんでした。もう一度お試しください。';
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        if (scope == widget.shortcutScope && message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(SkoLanguageController.tr(message))),
          );
        }
      }
    }
  }

  void _route(TrafficRouteTarget target) {
    final scope = widget.shortcutScope;
    final loader =
        widget.routeLoader ?? TrafficRouteRepository.maybeCreate()?.load;
    if (scope == null || !scope.valid || loader == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('所属会社とログイン状態を確認してください。')));
      return;
    }
    _open(() => loader(scope, target), sameTab: true);
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(SkoLanguageController.tr('交通案内')),
        content: Text(
          SkoLanguageController.tr(
            '「自宅」「会社」は現在地と登録住所をGoogleマップに渡して、公共交通・徒歩の経路を開きます。最寄り駅・電車乗換・バス停の検索は外部サービス側で行います。「その他①」「その他②」は管理者が長押しして表示名とURLを変更できます。設定はこの端末のアカウント・会社別に保存します。交通カード本体を長押しすると並べ替えできます。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(SkoLanguageController.tr('閉じる')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SkoLanguageController.watch(context);
    final colors = Theme.of(context).colorScheme;

    Widget tile(String id, String label, Widget icon, VoidCallback? open) =>
        Tooltip(
          message: SkoLanguageController.tr(label),
      triggerMode: TooltipTriggerMode.manual,
          child: TextButton(
            key: ValueKey('traffic-$id'),
            onPressed: _opening ? null : open,
            style: trafficCompactStyle(context),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    SkoLanguageController.tr(label),
                    maxLines: 2,
                    style: TextStyle(fontSize: 10, height: trafficLabelLineHeight(context)),
                  ),
                ),
              ],
            ),
          ),
        );
    Widget legacy(TrafficDestination destination, String label) {
      final allowed = widget.availability.permits(destination);
      return tile(
        destination.name,
        label,
        TrafficDestinationIcon(
          key: ValueKey('traffic-icon-${destination.name}'),
          destination: destination,
          enabled: allowed && !_opening,
        ),
        allowed
            ? () => _open(() async => trafficDestinationUri(destination))
            : null,
      );
    }

    Widget other(int slot, String label) => TrafficPersonalShortcut(
      key: ValueKey('traffic-other-$slot'),
      scope: widget.shortcutScope,
      slot: slot,
      emptyLabel: label,
      canEdit: widget.canEditShortcuts,
      compact: true,
      webOnly: true,
      open: widget.launcher,
    );

    Widget row(List<Widget> tiles) => Row(
      children: [
        for (final tile in tiles)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: tile,
            ),
          ),
      ],
    );

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row([
                    tile(
                      'home',
                      '自宅',
                      const Icon(Icons.home_outlined, size: 20),
                      () => _route(TrafficRouteTarget.home),
                    ),
                    legacy(TrafficDestination.nearestStation, '最寄り駅'),
                    legacy(TrafficDestination.trainTransfer, '電車乗換'),
                    legacy(TrafficDestination.busStop, 'バス停'),
                  ]),
                  const SizedBox(height: 2),
                  row([
                    tile(
                      'company',
                      '会社',
                      const Icon(Icons.business_outlined, size: 20),
                      () => _route(TrafficRouteTarget.company),
                    ),
                    tile(
                      'rain',
                      '雨雲',
                      const Icon(CupertinoIcons.cloud_rain, size: 16),
                      () => _open(
                        () async => Uri.parse(
                          'https://weather.yahoo.co.jp/weather/zoomradar/',
                        ),
                      ),
                    ),
                    other(1, 'その他①'),
                    other(2, 'その他②'),
                  ]),
                ],
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}

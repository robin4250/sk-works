import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/branding/sko_theme.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/features/home/friendly_home_content.dart';
import 'package:sk_works/features/home/home_attention_repository.dart';
import 'package:sk_works/features/home/home_membership_repository.dart';
import 'package:sk_works/features/home/home_action_order_policy.dart';
import 'package:sk_works/features/traffic/traffic_home_card.dart';
import 'package:sk_works/features/traffic/traffic_link_policy.dart';
import 'package:sk_works/features/settings/master_feature_availability.dart';

void main() {
  const enabled = TrafficAvailability(nearestStation: true, trainTransfer: true, busStop: true);
  Future<void> pump(WidgetTester tester, {TrafficAvailability availability = enabled, TrafficLinkLauncher? launcher}) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: SkoTheme.light(SkoTheme.palettes.first), home: Scaffold(body: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.6)),
      child: TrafficHomeCard(availability: availability, launcher: launcher),
    ))));
  }
  test('approved external destinations contain no SKO location or identity', () {
    final station = trafficDestinationUri(TrafficDestination.nearestStation);
    expect(station.scheme, 'https');
    expect(station.host, 'www.google.com');
    expect(station.queryParameters, {'api': '1', 'query': '最寄り駅'});
    expect(trafficDestinationUri(TrafficDestination.busStop).queryParameters['query'], '近くのバス停');
    expect(trafficDestinationUri(TrafficDestination.trainTransfer).toString(), 'https://transit.yahoo.co.jp/');
    final old = MasterFeatureAvailability.fromJson({'vehicle_management': true, 'route_assignment': false});
    expect(old.vehicleManagement, isTrue);
    expect(old.routeAssignment, isFalse);
    expect(old.trafficNearestStation, isFalse);
  });
  testWidgets('four fixed slots fit narrow enlarged text and launch three links', (tester) async {
    final opened = <Uri>[];
    await pump(tester, launcher: (uri) async { opened.add(uri); return true; });
    final buttons = TrafficDestination.values.map((d) => find.byKey(ValueKey('traffic-${d.name}'))).toList();
    final positions = buttons.map(tester.getRect).toList();
    expect(positions[0].width, positions[1].width);
    expect(positions[1].width, positions[2].width);
    expect(positions[0].top, positions[2].top);
    expect(find.byKey(const ValueKey('traffic-future-slot')), findsOneWidget);
    for (final button in buttons) { await tester.tap(button); await tester.pumpAndSettle(); }
    expect(opened, TrafficDestination.values.map(trafficDestinationUri).toList());
    expect(tester.takeException(), isNull);
  });
  testWidgets('OFF cannot launch and other slots do not move', (tester) async {
    var calls = 0;
    await pump(tester, availability: const TrafficAvailability(nearestStation: false, trainTransfer: true, busStop: false), launcher: (_) async { calls++; return true; });
    await tester.tap(find.byKey(const ValueKey('traffic-nearestStation')));
    await tester.tap(find.byKey(const ValueKey('traffic-busStop')));
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('traffic-trainTransfer')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('pending launch suppresses repeats; failure is visible and can retry', (tester) async {
    final result = Completer<bool>();
    var calls = 0;
    await pump(tester, launcher: (_) { calls++; return result.future; });
    final station = find.byKey(const ValueKey('traffic-nearestStation'));
    await tester.tap(station); await tester.pump();
    await tester.tap(station); await tester.pump();
    expect(calls, 1);
    result.complete(false); await tester.pumpAndSettle();
    expect(find.text('外部サービスを開けませんでした。もう一度お試しください。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('help explains external location processing', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('交通案内のヘルプ')); await tester.pumpAndSettle();
    expect(find.textContaining('現在地の確認や検索は外部サービス側'), findsOneWidget);
  });
  test('master traffic read is independent and discards stale actor responses', () async {
    final pending = Completer<MasterFeatureAvailability>();
    var current = true;
    final loaded = <TrafficAvailability>[];
    final result = loadTrafficMasterFlags(fetch: () => pending.future, isCurrent: () => current, onLoaded: loaded.add);
    current = false;
    pending.complete(const MasterFeatureAvailability(vehicleManagement: true, routeAssignment: true, trafficBusStop: true));
    expect(await result, isNull);
    expect(loaded, isEmpty);
    current = true;
    final good = await loadTrafficMasterFlags(fetch: () async => const MasterFeatureAvailability(vehicleManagement: false, routeAssignment: true, trafficNearestStation: true), isCurrent: () => current, onLoaded: loaded.add);
    expect(good!.vehicleManagement, isFalse);
    expect(loaded.single.nearestStation, isTrue);
    final failed = await loadTrafficMasterFlags(fetch: () async => throw StateError('unreadable'), isCurrent: () => current, onLoaded: loaded.add);
    expect(failed, isNull);
    expect(loaded.last, TrafficAvailability.unavailable);
  });
  testWidgets('English traffic labels fit 320px at 1.6 scale', (tester) async {
    SkoLanguageController.pack.value = LanguagePackRegistry.resolve('en');
    addTearDown(() => SkoLanguageController.pack.value = LanguagePackRegistry.resolve('ja'));
    await pump(tester);
    expect(find.text('Station'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Bus stop'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('home traffic follows weather; handle avoids links/help; visibility and saved order survive', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> home(bool show) => tester.pumpWidget(MaterialApp(theme: SkoTheme.light(SkoTheme.palettes.first), home: Scaffold(body: FriendlyHomeContent(
      identity: const HomeIdentity(role: 'worker', companyName: '会社', displayName: '本人'),
      requiredDocumentAttention: const RequiredDocumentAttention(missingCount: 0, missingNames: [], needsLicense: false, needsQualification: false),
      moduleEnabled: (_) => true,
      showAttendanceReport: false,
      showTodayAttendance: false,
      weatherCard: const SizedBox(key: ValueKey('test-weather'), height: 80),
      trafficCard: const TrafficHomeCard(key: ValueKey('test-traffic'), availability: enabled),
      showTrafficGuidance: show,
      onOpen: (_) async {}, onRefresh: () async {}, onReorderAction: (_, _) async {},
    ))));
    await home(true); await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('test-weather'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('test-traffic'))).dy));
    final handle = tester.getRect(find.byKey(const ValueKey('home-reorder-traffic_guidance')));
    expect(handle.overlaps(tester.getRect(find.byTooltip('交通案内のヘルプ'))), isFalse);
    for (final destination in TrafficDestination.values) {
      expect(handle.overlaps(tester.getRect(find.byKey(ValueKey('traffic-${destination.name}')))), isFalse);
    }
    await home(false); await tester.pump();
    expect(find.byKey(const ValueKey('test-traffic')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(normalizeHomeActionOrder([], ['attendance_today','weather_forecast','traffic_guidance','home_attention','today_line']), ['attendance_today','weather_forecast','traffic_guidance','home_attention','today_line']);
    expect(normalizeHomeActionOrder(['traffic_guidance','weather_forecast','today_line'], ['weather_forecast','traffic_guidance','today_line']), ['traffic_guidance','weather_forecast','today_line']);
  });

}

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

// One UI-isolate ordering for every outgoing journal begin/read/retirement and
// terminal cleanup. This is not a cross-isolate or database transaction lock.
Future<void> _tail = Future<void>.value();
Future<T> siteOrderJournalSerial<T>(Future<T> Function() action) {
  final result = Completer<T>();
  _tail = _tail.then((_) async {
    try {
      result.complete(await action());
    } catch (error, stack) {
      result.completeError(error, stack);
    }
  });
  return result.future;
}

String siteOrderDeliveryMarkerPrefix(
  String actor,
  String company,
  String site,
) {
  final uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');
  if (![actor, company, site].every(uuid.hasMatch))
    throw StateError('注文の本人・会社・現場を確認できません。');
  return 'sko.site_order.delivery_recorded.v1.$actor.$company.$site.';
}

String siteOrderDeliveryMarkerKey(
  String actor,
  String company,
  String site,
  String request,
) {
  if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$')
      .hasMatch(request))
    throw StateError('注文の保存情報を確認できません。');
  return '${siteOrderDeliveryMarkerPrefix(actor, company, site)}$request';
}

void siteOrderRequireUnrecorded(
  SharedPreferences preferences,
  String actor,
  String company,
  String site,
  String request,
) {
  if (preferences.containsKey(
    siteOrderDeliveryMarkerKey(actor, company, site, request),
  )) {
    throw StateError('この注文の共有結果は保管済みです。再送せず保存状態を確認してください。');
  }
}

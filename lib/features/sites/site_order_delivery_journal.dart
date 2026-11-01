import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'site_order_journal_serial.dart';
import 'site_order_outgoing_consent.dart';
import 'site_order_outgoing_execution.dart';

/// Local record of observed sender delivery, never recipient approval.
class SiteOrderDeliveryRecord {
  SiteOrderDeliveryRecord._(this._value);
  final Map<String, dynamic> _value;
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_value)) as Map);
  SiteOrderConsentReference get reference =>
      SiteOrderConsentReference.fromJson(_value['reference']);
  String get jobId => _value['job_id'] as String;
  String get recipientCompanyId => _value['recipient_company_id'] as String;
  String get packageId => _value['package_id'] as String;
  factory SiteOrderDeliveryRecord.fromObservation(
    String actor,
    String company,
    SiteOrderConsentReference reference,
    SiteOrderExecutionObservation observation,
  ) {
    if (!observation.binds(reference, company) ||
        !observation.originalSaved ||
        !observation.recipientStored ||
        observation.unresolved) {
      throw StateError('共有先への保存結果が未確認です。元の注文記録を保持してください。');
    }
    final payload = <String, dynamic>{
      'contract_version': 1,
      'stage': 'sender_delivery_recorded',
      'actor_id': actor,
      'company_id': company,
      'reference': reference.toJson(),
      'job_id': observation.jobId,
      'render_hash': observation.renderHash,
      'recipient_company_id': observation.recipientCompanyId,
      'original_receipt_id': observation.originalReceiptId,
      'pdf_sha256': observation.pdfHash,
      'pdf_byte_length': observation.pdfByteLength,
      'package_id': observation.packageId,
      'recipient_approval_state': 'not_checked',
      'device_push_confirmed': false,
    };
    return SiteOrderDeliveryRecord.fromJson(
      {
        ...payload,
        'observation_sha256': siteOrderDeliveryObservationDigest(payload),
      },
      actor,
      company,
      reference.prepare.siteId,
      reference.prepare.requestId,
    );
  }
  factory SiteOrderDeliveryRecord.fromJson(
    Object? raw,
    String actor,
    String company,
    String site,
    String request,
  ) => SiteOrderDeliveryRecord._(
    siteOrderParseDeliveryMarker(raw, actor, company, site, request),
  );
}

/// Only the marker is appended. Original prepare/consent/execution bytes remain.
/// The caller must obtain fresh exact server status before invoking record.
class SiteOrderDeliveryJournal {
  SiteOrderDeliveryJournal({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;
  final Future<SharedPreferences> Function() _preferences;
  Future<SiteOrderDeliveryRecord> record(
    String actor,
    String company,
    SiteOrderConsentReference reference,
    SiteOrderExecutionObservation observation, {
    required Future<void> Function() verifyScope,
  }) => siteOrderJournalSerial(() async {
    final value = SiteOrderDeliveryRecord.fromObservation(
      actor,
      company,
      reference,
      observation,
    );
    final p = await _preferences();
    await p.reload();
    final site = reference.prepare.siteId,
        request = reference.prepare.requestId;
    await verifyScope();
    final existing = siteOrderDeliveryMarkers(p, actor, company, site);
    final key = siteOrderDeliveryMarkerKey(actor, company, site, request),
        encoded = jsonEncode(value.toJson());
    if (existing[request] != null) {
      if (!siteOrderSameJournalJson(jsonEncode(existing[request]), encoded)) {
        throw StateError('別の共有結果が保管されています。上書きしません。');
      }
      await verifyScope();
      return value;
    }
    // Mandatory source records must exist before a marker can hide any pending
    // entry. Optional original/share intents must also match if present.
    final sources = {
      'sko.site_order.outgoing.v1.$actor.$company.$site.$request': jsonEncode(
        reference.prepare.toJson(),
      ),
      'sko.site_order.consent.v1.$actor.$company.$site.$request': jsonEncode(
        reference.toJson(),
      ),
    };
    for (final entry in sources.entries) {
      final raw = p.getString(entry.key);
      if (raw == null || !siteOrderSameJournalJson(raw, entry.value)) {
        throw StateError('元の注文確認が不足・不一致です。記録を保持してください。');
      }
    }
    final executionPrefix =
        'sko.site_order.execution.v1.$actor.$company.$site.$request.';
    if (p.getKeys().any(
      (key) =>
          key.startsWith(executionPrefix) &&
          ![
            'original',
            'share',
          ].contains(key.substring(executionPrefix.length)),
    )) {
      throw StateError('不明な共有処理の元記録を保持しています。');
    }
    for (final stage in ['original', 'share']) {
      final key =
          'sko.site_order.execution.v1.$actor.$company.$site.$request.$stage';
      if (p.containsKey(key)) {
        final raw = p.getString(key);
        if (raw == null ||
            !siteOrderSameJournalJson(raw, jsonEncode(reference.toJson()))) {
          throw StateError('原本・共有の元記録が一致しません。');
        }
      }
    }
    await verifyScope();
    if (!await p.setString(key, encoded)) {
      throw StateError('共有結果の保管を確認できません。元の記録を保持しています。');
    }
    // No source record is removed, even after a scope loss or simulated crash.
    await verifyScope();
    await p.reload();
    final persisted = siteOrderDeliveryMarkers(
      p,
      actor,
      company,
      site,
    )[request];
    if (persisted == null ||
        !siteOrderSameJournalJson(jsonEncode(persisted), encoded)) {
      throw StateError('共有結果の保管が未確認です。状態を再照会してください。');
    }
    await verifyScope();
    return value;
  });
  Future<List<SiteOrderDeliveryRecord>> read(
    String actor,
    String company,
    String site,
  ) => siteOrderJournalSerial(() async {
    final p = await _preferences();
    await p.reload();
    final markers = siteOrderDeliveryMarkers(p, actor, company, site);
    return List.unmodifiable(
      markers.entries.map(
        (e) => SiteOrderDeliveryRecord.fromJson(
          e.value,
          actor,
          company,
          site,
          e.key,
        ),
      ),
    );
  });
}

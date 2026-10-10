import 'dart:convert';
import 'dart:typed_data';

import '../../international/language_controller.dart';
import 'daily_report_repository.dart';

/// Frozen report evidence; failed download never changes the saved photo status.
class DailyReportPdfEvidence {
  DailyReportPdfEvidence({required this.record, Uint8List? photoBytes,
    this.downloadFailed = false})
    : photoBytes = photoBytes == null ? null : Uint8List.fromList(photoBytes).asUnmodifiableView();

  final DailyReportEvidenceRecord record;
  final Uint8List? photoBytes;
  final bool downloadFailed;

  List<String> get captions => [
    '${record.workerName} / ${SkoLanguageController.tr(record.eventLabel)}',
    if (record.stopLabel != null) '${SkoLanguageController.tr('対象現場')}: ${record.stopLabel}',
    if (record.originKind != null) SkoLanguageController.tr(record.originKind == 'company' ? '会社出勤後に現場へ' : '直行直帰'),
    '${SkoLanguageController.tr(record.eventType.startsWith('route_') ? '記録時刻' : '勤怠登録時刻')}: ${record.confirmedAt.toIso8601String()}',
    if (!record.isTimeOnly) record.photoCapturedAt == null
      ? SkoLanguageController.tr('撮影日時未取得')
      : '${SkoLanguageController.tr('撮影日時')}: ${record.photoCapturedAt!.toIso8601String()}',
    if (record.photoObservedAt != null)
      '${SkoLanguageController.tr('写真観測時刻')}: ${record.photoObservedAt!.toIso8601String()}',
    if (record.gpsCapturedAt != null)
      '${SkoLanguageController.tr('GPS取得時刻')}: ${record.gpsCapturedAt!.toIso8601String()}',
    if (!record.isTimeOnly) '${SkoLanguageController.tr('撮影住所')}: ${record.capturedAddress?.trim().isNotEmpty == true ? record.capturedAddress : SkoLanguageController.tr('未取得')}',
    if (record.hasLocation) 'GPS: ${record.latitude}, ${record.longitude}',
    if (!record.isTimeOnly && record.photoStatus != null) '${SkoLanguageController.tr('写真の保存状態')}: ${_status(record.photoStatus)}',
    if (!record.isTimeOnly && record.gpsStatus != null) '${SkoLanguageController.tr('GPSの取得状態')}: ${_status(record.gpsStatus)}',
    if (downloadFailed) SkoLanguageController.tr('保存済み写真を読み込めませんでした'),
    if (record.storagePath.isEmpty) SkoLanguageController.tr(record.missingPhotoLabel),
  ];

  Object get fingerprintData => [record.id, record.workerName, record.eventType, record.isTimeOnly,
    record.confirmedAt.toIso8601String(), record.photoCapturedAt?.toIso8601String(),
    record.gpsCapturedAt?.toIso8601String(), record.photoObservedAt?.toIso8601String(),
    record.storageBucket, record.sourceClockInId, record.routeStopId, record.stopLabel,
    record.originKind, record.storagePath, record.latitude,
    record.longitude, record.accuracyM, record.photoStatus, record.gpsStatus,
    record.capturedAddress, downloadFailed, photoBytes == null ? null : base64Encode(photoBytes!)];

  static String _status(String? status) => SkoLanguageController.tr(switch (status) {
    'uploaded' || 'acquired' => '登録済み',
    'upload_failed' => '送信失敗',
    'failed' => '取得失敗',
    _ => '未登録',
  });
}

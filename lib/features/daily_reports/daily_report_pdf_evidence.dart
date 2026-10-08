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
    '${record.workerName} / ${SkoLanguageController.tr(record.eventType == 'clock_out' ? '退勤' : '出勤')}',
    '${SkoLanguageController.tr('勤怠登録時刻')}: ${record.confirmedAt.toIso8601String()}',
    record.photoCapturedAt == null
      ? SkoLanguageController.tr('撮影日時未取得')
      : '${SkoLanguageController.tr('撮影日時')}: ${record.photoCapturedAt!.toIso8601String()}',
    if (record.gpsCapturedAt != null)
      '${SkoLanguageController.tr('GPS取得時刻')}: ${record.gpsCapturedAt!.toIso8601String()}',
    '${SkoLanguageController.tr('撮影住所')}: ${record.capturedAddress?.trim().isNotEmpty == true ? record.capturedAddress : SkoLanguageController.tr('未取得')}',
    if (record.hasLocation) 'GPS: ${record.latitude}, ${record.longitude}',
    if (record.photoStatus != null) '${SkoLanguageController.tr('写真の保存状態')}: ${_status(record.photoStatus)}',
    if (record.gpsStatus != null) '${SkoLanguageController.tr('GPSの取得状態')}: ${_status(record.gpsStatus)}',
    if (downloadFailed) SkoLanguageController.tr('保存済み写真を読み込めませんでした'),
    if (record.storagePath.isEmpty) SkoLanguageController.tr('写真未登録・送信失敗'),
  ];

  Object get fingerprintData => [record.id, record.workerName, record.eventType,
    record.confirmedAt.toIso8601String(), record.photoCapturedAt?.toIso8601String(),
    record.gpsCapturedAt?.toIso8601String(), record.storagePath, record.latitude,
    record.longitude, record.accuracyM, record.photoStatus, record.gpsStatus,
    record.capturedAddress, downloadFailed, photoBytes == null ? null : base64Encode(photoBytes!)];

  static String _status(String? status) => SkoLanguageController.tr(switch (status) {
    'uploaded' || 'acquired' => '登録済み',
    'upload_failed' => '送信失敗',
    'failed' => '取得失敗',
    _ => '未登録',
  });
}

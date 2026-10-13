import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_evidence_address.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';

void main() {
  test(
    'normalizes Japanese recorded street components without joining numbers',
    () {
      expect(normalizeRecordedAddress(' 東京都 墨田区 横川 1 9 '), '東京都墨田区横川1-9');
      expect(normalizeRecordedAddress('東京都 墨田区 横川 1丁目 9番地'), '東京都墨田区横川1-9');
      expect(
        normalizeRecordedAddress('北海道 札幌市 中央区 北一条西 2丁目 3番 4号'),
        '北海道札幌市中央区北一条西2-3-4',
      );
      expect(
        normalizeRecordedAddress('  10 Main Street, New York  '),
        '10 Main Street, New York',
      );
      expect(normalizeRecordedAddress(' '), isNull);
    },
  );

  test('retains saved address without a new lookup and resolves exact recorded coordinates', () async {
    final calls = <List<double>>[];
    final resolver = DailyReportEvidenceAddressResolver(
      reverseGeocode: ({required latitude, required longitude}) async {
        calls.add([latitude, longitude]);
        return '東京都 墨田区 横川 1丁目 9番地';
      },
    );
    expect(
      await resolver.resolve(savedAddress: '東京都 墨田区 横川 1 9'),
      '東京都墨田区横川1-9',
    );
    expect(calls, isEmpty);
    final results = await Future.wait([
      resolver.resolve(
        latitude: 35.703,
        longitude: 139.811,
        gpsStatus: 'acquired',
      ),
      resolver.resolve(latitude: 35.703, longitude: 139.811),
    ]);
    expect(results, everyElement('東京都墨田区横川1-9'));
    expect(calls, [
      [35.703, 139.811],
    ]);
  });

  test(
    'manual, failed GPS and invalid coordinates cannot invent an address',
    () async {
      var calls = 0;
      final resolver = DailyReportEvidenceAddressResolver(
        reverseGeocode: ({required latitude, required longitude}) async {
          calls++;
          return 'unexpected';
        },
      );
      expect(
        await resolver.resolve(
          timeOnly: true,
          savedAddress: '会社住所',
          latitude: 35,
          longitude: 139,
        ),
        isNull,
      );
      expect(
        await resolver.resolve(
          latitude: 35,
          longitude: 139,
          gpsStatus: 'failed',
        ),
        isNull,
      );
      expect(
        await resolver.resolve(latitude: double.nan, longitude: 139),
        isNull,
      );
      expect(await resolver.resolve(latitude: 35, longitude: 181), isNull);
      expect(await resolver.resolve(latitude: 35), isNull);
      expect(calls, 0);
    },
  );

  test('lookup failure preserves recorded location, photo, event identity and PDF fallback', () async {
    final resolver = DailyReportEvidenceAddressResolver(
      reverseGeocode: ({required latitude, required longitude}) async =>
          throw StateError('offline'),
    );
    final original = DailyReportEvidenceRecord(
      id: 'saved-id',
      workerName: '本人',
      eventType: 'clock_in',
      confirmedAt: DateTime(2026, 10, 11, 9),
      storagePath: 'saved.jpg',
      latitude: 35.703,
      longitude: 139.811,
      gpsStatus: 'acquired',
      photoStatus: 'uploaded',
      sourceClockInId: 'source-id',
    );
    final record = original.withCapturedAddress(
      await resolver.resolve(
        latitude: original.latitude,
        longitude: original.longitude,
        gpsStatus: original.gpsStatus,
      ),
    );
    expect(record.id, original.id);
    expect(record.confirmedAt, original.confirmedAt);
    expect(record.sourceClockInId, original.sourceClockInId);
    expect(record.storagePath, original.storagePath);
    expect(record.hasLocation, isTrue);
    expect(record.capturedAddress, isNull);
    expect(
      DailyReportPdfEvidence(record: record).captions.join("\n"),
      contains('未取得'),
    );
    final enriched = record.withCapturedAddress('東京都墨田区横川1-9');
    expect(
      DailyReportPdfEvidence(record: enriched).captions.join("\n"),
      contains('東京都墨田区横川1-9'),
    );
    expect(
      original.capturedAddress,
      isNull,
      reason: 'stored snapshot stays unchanged',
    );
  });
}

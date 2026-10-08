import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 10, 31);
  DailyReportEvidenceRecord record({String address = '東京都新宿区 合成テスト住所',
      String path = 'synthetic/photo.png', DateTime? capturedAt}) =>
    DailyReportEvidenceRecord(id: 'source-evidence', workerName: '合成運転手',
      eventType: 'clock_out', confirmedAt: DateTime(2026, 11, 1, 7, 5),
      storagePath: path, latitude: 35.68, longitude: 139.76,
      photoStatus: path.isEmpty ? 'upload_failed' : 'uploaded', gpsStatus: 'acquired',
      capturedAddress: address, photoCapturedAt: capturedAt,
      gpsCapturedAt: DateTime(2026, 11, 1, 7));

  test('PDF fingerprint changes when photo provenance or bytes change', () {
    String key(DailyReportPdfEvidence evidence) => DailyReportPdfService.fingerprint(
      date: date, siteName: '合成現場', workers: [], workDescription: '合成作業',
      report: null, evidence: [evidence]);
    final first = DailyReportPdfEvidence(record: record(), photoBytes: Uint8List.fromList([1]));
    expect(key(first), isNot(key(DailyReportPdfEvidence(record: record(address: '別の実取得住所'),
      photoBytes: Uint8List.fromList([1])))));
    expect(key(first), isNot(key(DailyReportPdfEvidence(record: record(),
      photoBytes: Uint8List.fromList([2])))));
    expect(key(first), isNot(key(DailyReportPdfEvidence(record: record(), downloadFailed: true))));
  });

  test('unknown shutter time is not replaced by attendance registration time', () {
    final captions = DailyReportPdfEvidence(record: record(path: '')).captions.join('\n');
    expect(captions, contains('撮影日時未取得'));
    expect(captions, contains('勤怠登録時刻: 2026-11-01T07:05:00.000'));
    expect(captions, contains('送信失敗'));
    expect(captions, isNot(contains('撮影日時: 2026-11-01T07:05')));
  });

  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('actual daily report PDF embeds photos and preserves failed evidence captions', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final directory = Directory(Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
      Directory.systemTemp.createTempSync('sko-daily-evidence-').path);
    directory.createSync(recursive: true);
    final bytes = await DailyReportPdfService.buildPdf(date: date,
      siteName: '合成現場', workers: [DailyReportWorkerDraft(workerId: 'synthetic-driver',
        workerName: '合成運転手')], workDescription: '合成作業', report: null,
      regularFont: font, boldFont: font, evidence: [
        DailyReportPdfEvidence(record: record(capturedAt: DateTime(2026, 11, 1, 6, 59)),
          photoBytes: base64Decode('iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAIAAABqVuVZAAACA0lEQVR4nO3bPU4DMRAF4BfCMThKJMqUuQUFh0iRQ1DkFpQpkXIK6jRcAQmJYqXVar3rN7bHY4jnVcD+ePJl7F2xyebz6xue9Ty0LuCvx4FIHIjEgUgciMSBSByIxIFIHIjkMb75+eXNpo6G+Ti/RrZ6B5E4EAmZYmPiffgfI1w9vINIHIikU6DdaS/cs0egQefn6V2yc3dA096RGPUFNJtZ29uBHtIRUIYO+gGa6VyPF+GBXQBl66AHoBId3D1QoQ7uG6hcB5ZAQ7nyW1iV4cbk6cAMaKpjYKSlAxugUGR32tdjUtSBAVAEwqCVCnVQFUjSJupG0xOW66Ae0OIrvx4vYdGK001dB5WA1nRmP9BDygctj/R/0vKEhYYiw19mew6/5r3zugvzNModJNGJb8pohHo60AVK0onskGRUVQeKQBk6427ZK3dtHagALb6Y1FozWslAB+VA8QtWUpKMbHRQCKSoMx4rmW5mOigBWpxWKrXGW8lSB9n3QeWLTjyRG6V6gy4mp4PMCo2f1kAHGUDGb+PayW10kDTF1JdkYcLpZqYDeQe10pmNpXUdkEcEtPgM27jQJiNCMsVCnSaFtgrvoNkz7K50kHoV600HQqChiTrUgfwyv70devhQeZh7fvSsEgci2fi3nuPxDiJxIBIHInEgEgcicSASByJxIBIHIvkFUQHikY9nhEsAAAAASUVORK5CYII=')),
        DailyReportPdfEvidence(record: record(path: '', address: '')),
        DailyReportPdfEvidence(record: record(), downloadFailed: true),
      ]);
    final file = File('${directory.path}/daily_report_capture_evidence.pdf')..writeAsBytesSync(bytes);
    final result = await Process.run('python', ['-c',
      'import fitz,sys,json; d=fitz.open(sys.argv[1]); print(json.dumps({"pages":len(d),"text":"\\n".join(p.get_text() for p in d),"images":sum(len(p.get_images()) for p in d)},ensure_ascii=False)); [p.get_pixmap(matrix=fitz.Matrix(1,1)).save(sys.argv[2]+"/daily_report_capture_evidence_"+str(i+1)+".png") for i,p in enumerate(d)]',
      file.path, directory.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final actual = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    expect(actual['pages'], 4);
    expect(actual['images'], greaterThanOrEqualTo(1));
    final text = actual['text'] as String;
    expect(text, contains('東京都新宿区 合成テスト住所'));
    expect(text, contains('2026-11-01T06:59:00.000'));
    expect(text, contains('撮影日時未取得'));
    expect(text, contains('送信失敗'));
    expect(text, contains('保存済み写真を読み込めませんでした'));
  }, skip: fontPath == null ? 'Set SKO_PDF_FONT_PATH for actual Flutter PDF rendering.' : false);
}

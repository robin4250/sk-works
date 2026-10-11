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
  final testPhoto = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAIAAABqVuVZAAACA0lEQVR4nO3bPU4DMRAF4BfCMThKJMqUuQUFh0iRQ1DkFpQpkXIK6jRcAQmJYqXVar3rN7bHY4jnVcD+ePJl7F2xyebz6xue9Ty0LuCvx4FIHIjEgUgciMSBSByIxIFIHIjkMb75+eXNpo6G+Ti/RrZ6B5E4EAmZYmPiffgfI1w9vINIHIikU6DdaS/cs0egQefn6V2yc3dA096RGPUFNJtZ29uBHtIRUIYO+gGa6VyPF+GBXQBl66AHoBId3D1QoQ7uG6hcB5ZAQ7nyW1iV4cbk6cAMaKpjYKSlAxugUGR32tdjUtSBAVAEwqCVCnVQFUjSJupG0xOW66Ae0OIrvx4vYdGK001dB5WA1nRmP9BDygctj/R/0vKEhYYiw19mew6/5r3zugvzNModJNGJb8pohHo60AVK0onskGRUVQeKQBk6427ZK3dtHagALb6Y1FozWslAB+VA8QtWUpKMbHRQCKSoMx4rmW5mOigBWpxWKrXGW8lSB9n3QeWLTjyRG6V6gy4mp4PMCo2f1kAHGUDGb+PayW10kDTF1JdkYcLpZqYDeQe10pmNpXUdkEcEtPgM27jQJiNCMsVCnSaFtgrvoNkz7K50kHoV600HQqChiTrUgfwyv70devhQeZh7fvSsEgci2fi3nuPxDiJxIBIHInEgEgcicSASByJxIBIHIvkFUQHikY9nhEsAAAAASUVORK5CYII=');
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
    expect(DailyReportPdfEvidence(record: record()).captions,
      contains('撮影住所: 東京都新宿区 合成テスト住所'));
    expect(captions, contains('撮影日時未取得'));
    expect(captions, contains('勤怠登録時刻: 2026-11-01T07:05:00.000'));
    expect(captions, contains('送信失敗'));
    expect(captions, isNot(contains('撮影日時: 2026-11-01T07:05')));
  });

  test('time-only arrivals and moves preserve actual time without photo failures', () {
    for (final kind in ['route_arrival', 'route_move', 'clock_in', 'clock_out']) {
      final item = DailyReportEvidenceRecord(id: kind, workerName: '本人',
        eventType: kind, confirmedAt: DateTime(2026, 10, 11, 10, 25),
        storagePath: '', stopLabel: '実際の現場',
        timeOnly: true, photoStatus: 'missing', gpsStatus: 'missing');
      final captions = DailyReportPdfEvidence(record: item).captions.join('\n');
      expect(item.isTimeOnly, isTrue);
      expect(captions, contains(item.eventLabel));
      expect(captions, contains('2026-10-11T10:25:00.000'));
      expect(captions, contains('実際の現場'));
      expect(captions, contains('時刻のみの記録'));
      expect(captions, isNot(contains('失敗')));
      expect(captions, isNot(contains('撮影日時未取得')));
    }
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
          photoBytes: testPhoto),
        DailyReportPdfEvidence(record: record(path: '', address: '')),
        DailyReportPdfEvidence(record: record(), downloadFailed: true),
        DailyReportPdfEvidence(record: DailyReportEvidenceRecord(id: 'route-capture',
          workerName: '合成運転手', eventType: 'route_stop', confirmedAt: DateTime(2026, 11, 1, 6, 30),
          storagePath: '', storageBucket: 'attendance-route-evidence',
          stopLabel: '登録済み途中現場', sourceClockInId: 'actual-route-start', routeStopId: 'actual-route-stop',
          originKind: 'company', photoStatus: 'upload_failed', gpsStatus: 'acquired',
          photoObservedAt: DateTime(2026, 11, 1, 6, 25),
          gpsCapturedAt: DateTime(2026, 11, 1, 6, 25), capturedAddress: '途中現場の実GPS住所',
          latitude: 35.68, longitude: 139.76)),
      ]);
    final file = File('${directory.path}/daily_report_capture_evidence.pdf')..writeAsBytesSync(bytes);
    final result = await Process.run('python', ['-c',
      'import fitz,sys,json; d=fitz.open(sys.argv[1]); print(json.dumps({"pages":len(d),"text":"\\n".join(p.get_text() for p in d),"images":sum(len(p.get_images()) for p in d)},ensure_ascii=False)); [p.get_pixmap(matrix=fitz.Matrix(1,1)).save(sys.argv[2]+"/daily_report_capture_evidence_"+str(i+1)+".png") for i,p in enumerate(d)]',
      file.path, directory.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final actual = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    expect(actual['pages'], 2);
    expect(actual['images'], greaterThanOrEqualTo(1));
    final text = actual['text'] as String;
    // PDF text extraction may omit a visual Japanese word-space. Keep the
    // original address exact in the caption contract above; normalize only
    // extracted whitespace, without weakening address or failure evidence.
    expect(text.replaceAll(RegExp(r'\s+'), ''),
      contains('東京都新宿区合成テスト住所'));
    expect(text, contains('2026/11/01 07:05'));
    expect(text, contains('送信失敗'));
    expect(text, contains('保存済み写真を読み込めませんでした'));
    expect(text.replaceAll(RegExp(r'\s+'), ''), contains('途中現場の実GPS住所'));
    expect(text, contains('2026/11/01 06:30'));
  }, skip: fontPath == null ? 'Set SKO_PDF_FONT_PATH for actual Flutter PDF rendering.' : false);
  test(
    'photo-only A4 uses the same photograph pages, without report body or manual tiles',
    () async {
      final font = pw.Font.ttf(
        ByteData.sublistView(await File(fontPath!).readAsBytes()),
      );
      final directory = Directory(
        Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
            Directory.systemTemp.createTempSync('sko-photo-pages-').path,
      )..createSync(recursive: true);
      final evidence = [
        DailyReportPdfEvidence(record: record(), photoBytes: testPhoto),
        DailyReportPdfEvidence(
          record: DailyReportEvidenceRecord(
            id: 'manual',
            workerName: '時刻のみの本人',
            eventType: 'clock_in',
            confirmedAt: date,
            storagePath: '',
            timeOnly: true,
          ),
        ),
      ];
      Future<Uint8List> pdf({
        required bool onlyPhotos,
        required List<DailyReportPdfEvidence> items,
      }) => DailyReportPdfService.buildPdf(
        date: date,
        siteName: '本文現場',
        workers: [
          DailyReportWorkerDraft(workerId: 'body', workerName: '本文作業者'),
        ],
        workDescription: '本文専用作業内容',
        report: null,
        evidence: items,
        photoPagesOnly: onlyPhotos,
        regularFont: font,
        boldFont: font,
      );
      final full = File('${directory.path}/daily_report_photo_pages_full.pdf')
        ..writeAsBytesSync(await pdf(onlyPhotos: false, items: evidence));
      final only = File('${directory.path}/daily_report_photo_pages_only.pdf')
        ..writeAsBytesSync(await pdf(onlyPhotos: true, items: evidence));
      final many = File('${directory.path}/daily_report_photo_pages_many.pdf')
        ..writeAsBytesSync(
          await pdf(
            onlyPhotos: true,
            items: [
              for (var i = 0; i < 9; i++)
                DailyReportPdfEvidence(
                  record: DailyReportEvidenceRecord(
                    id: 'photo-$i',
                    workerName: '写真本人-$i',
                    eventType: 'clock_in',
                    confirmedAt: date.add(Duration(minutes: i)),
                    storagePath: 'saved-$i.png',
                    capturedAddress: '実取得住所-$i',
                  ),
                  photoBytes: testPhoto,
                ),
            ],
          ),
        );
      final result = await Process.run('python', [
        '-c',
        'import fitz,sys,json,os; out=[]\nfor file in sys.argv[1:4]:\n d=fitz.open(file); out.append({"pages":len(d),"texts":[p.get_text() for p in d],"sizes":[list(p.rect) for p in d],"images":[len(p.get_images()) for p in d]}); [p.get_pixmap(matrix=fitz.Matrix(1,1)).save(os.path.splitext(file)[0]+"_"+str(i+1)+".png") for i,p in enumerate(d)]\nprint(json.dumps(out,ensure_ascii=False))',
        full.path,
        only.path,
        many.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final output = jsonDecode(result.stdout.toString()) as List;
      expect(output[0]['pages'], 2);
      expect(output[1]['pages'], 1);
      final photosText = output[1]['texts'][0] as String;
      expect(photosText, isNot(contains('本文専用作業内容')));
      expect(photosText, isNot(contains('時刻のみの本人')));
      expect(photosText, output[0]['texts'][1]);
      expect(
        output[0]['images'][0],
        greaterThan(0),
        reason: 'first-page corner contains the saved photograph',
      );
      expect(
        output[2]['pages'],
        3,
        reason: 'all nine photos continue across photograph pages',
      );
      final manyText = (output[2]['texts'] as List).join('\n');
      for (var i = 0; i < 9; i++) {
        expect(manyText, contains('写真本人-$i'));
      }
      for (final size in output[1]['sizes']) {
        expect(size[2], closeTo(595.28, 1));
        expect(size[3], closeTo(841.89, 1));
      }
      final noPhotos = await pdf(onlyPhotos: false, items: [evidence[1]]);
      final noPhotosFile = File(
        '${directory.path}/daily_report_photo_pages_none.pdf',
      )..writeAsBytesSync(noPhotos);
      final empty = await Process.run('python', [
        '-c',
        'import fitz,sys; print(len(fitz.open(sys.argv[1])))',
        noPhotosFile.path,
      ]);
      expect(empty.stdout.toString().trim(), '1');
      await expectLater(
        pdf(onlyPhotos: true, items: [evidence[1]]),
        throwsStateError,
      );
    },
    skip: fontPath == null
        ? 'Set SKO_PDF_FONT_PATH for actual PDF rendering.'
        : false,
  );
}

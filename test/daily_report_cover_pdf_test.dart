import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/daily_reports/daily_report_cover_layout.dart';
import 'package:sk_works/features/daily_reports/daily_report_photo_hit_target.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cover plan preserves counts and multi-line description exactly', () {
    for (final count in [0, 6, 12, 13, 37]) {
      final plan = DailyReportCoverLayout(photoCount: count, memberCount: 40);
      expect(plan.coverPhotos + plan.remainingPhotos, count);
      expect(plan.coverPhotos, lessThanOrEqualTo(12));
      expect(plan.coverMembers + plan.remainingMembers, 40);
    }
    for (final value in ['短文', '行\n' * 200, '作業内容😀' * 300]) {
      expect(dailyReportDescriptionParts(value).join(), value);
      expect(dailyReportDescriptionParts(value).every((part) => part.runes.length <= 168), isTrue);
    }
  });
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  test('actual A4 cover renders 0 6 12 overflow photos and all overflow members', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final output = Directory(Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
      Directory.systemTemp.createTempSync('daily-cover-').path)..createSync(recursive: true);
    final photo = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAGAAAABACAIAAABqVuVZAAACA0lEQVR4nO3bPU4DMRAF4BfCMThKJMqUuQUFh0iRQ1DkFpQpkXIK6jRcAQmJYqXVar3rN7bHY4jnVcD+ePJl7F2xyebz6xue9Ty0LuCvx4FIHIjEgUgciMSBSByIxIFIHIjkMb75+eXNpo6G+Ti/RrZ6B5E4EAmZYmPiffgfI1w9vINIHIikU6DdaS/cs0egQefn6V2yc3dA096RGPUFNJtZ29uBHtIRUIYO+gGa6VyPF+GBXQBl66AHoBId3D1QoQ7uG6hcB5ZAQ7nyW1iV4cbk6cAMaKpjYKSlAxugUGR32tdjUtSBAVAEwqCVCnVQFUjSJupG0xOW66Ae0OIrvx4vYdGK001dB5WA1nRmP9BDygctj/R/0vKEhYYiw19mew6/5r3zugvzNModJNGJb8pohHo60AVK0onskGRUVQeKQBk6427ZK3dtHagALb6Y1FozWslAB+VA8QtWUpKMbHRQCKSoMx4rmW5mOigBWpxWKrXGW8lSB9n3QeWLTjyRG6V6gy4mp4PMCo2f1kAHGUDGb+PayW10kDTF1JdkYcLpZqYDeQe10pmNpXUdkEcEtPgM27jQJiNCMsVCnSaFtgrvoNkz7K50kHoV600HQqChiTrUgfwyv70devhQeZh7fvSsEgci2fi3nuPxDiJxIBIHInEgEgcicSASByJxIBIHIvkFUQHikY9nhEsAAAAASUVORK5CYII=');
    for (final count in [0, 6, 12, 13]) {
      final evidence = [for (var i = 0; i < count; i++) DailyReportPdfEvidence(
        record: DailyReportEvidenceRecord(id: 'photo-$i', workerName: '写真$i',
          eventType: 'clock_in', confirmedAt: DateTime(2026, 10, 30, 8, i),
          storagePath: 'private/$i.png', capturedAddress: '実取得住所$i'), photoBytes: photo)];
      final memberCount = count == 13 ? 40 : 6;
      final targets = <DailyReportPhotoHitTarget>[];
      final bytes = await DailyReportPdfService.buildPdf(date: DateTime(2026, 10, 30),
        siteName: '実在対象の合成現場', workers: [for (var i = 0; i < memberCount; i++)
          DailyReportWorkerDraft(workerId: 'member-$i', workerName: 'メンバー$i')],
        workDescription: '安全確認と足場作業', report: null, evidence: evidence,
        regularFont: font, boldFont: font, onPhotoLayout: targets.add);
      final file = File('${output.path}/daily_cover_$count.pdf')..writeAsBytesSync(bytes);
      final result = await Process.run('python', ['-c',
        'import fitz,sys,json,os; d=fitz.open(sys.argv[1]); print(json.dumps({"pages":len(d),"texts":[p.get_text() for p in d],"sizes":[list(p.rect) for p in d],"images":[len(p.get_image_info()) for p in d]},ensure_ascii=False)); [p.get_pixmap(matrix=fitz.Matrix(1.3,1.3)).save(os.path.splitext(sys.argv[1])[0]+"_"+str(i+1)+".png") for i,p in enumerate(d)]', file.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final actual = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final texts = (actual['texts'] as List).cast<String>();
      expect(actual['pages'], count <= 12 ? 1 : greaterThan(1));
      expect(actual['images'][0], count.clamp(0, 12));
      expect(targets.map((t) => t.photoIndex).toSet(), {for (var i = 0; i < count; i++) i});
      expect(targets.where((t) => t.pageIndex == 0).length, count.clamp(0, 12));
      for (final target in targets) {
        expect(target.bounds.left, inInclusiveRange(0, 1));
        expect(target.bounds.right, inInclusiveRange(0, 1));
        expect(target.bounds.top, inInclusiveRange(0, 1));
        expect(target.bounds.bottom, inInclusiveRange(0, 1));
      }
      expect(texts.first, contains('メンバー'));
      for (var i = 0; i < count; i++) {
        expect(texts.join(), contains('実取得住所$i'));
        expect(evidence[i].photoBytes, orderedEquals(photo), reason: 'original bytes stay immutable');
      }
      for (var i = 0; i < memberCount; i++) {
        expect(texts.join(), contains('メンバー$i'));
      }
      for (final size in actual['sizes']) {
        expect(size[2], closeTo(595.28, 1)); expect(size[3], closeTo(841.89, 1));
      }
    }
  }, skip: fontPath == null ? 'Requires actual PDF font fixture' : false);
}

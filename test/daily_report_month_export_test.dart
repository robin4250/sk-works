import 'dart:typed_data';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_zip.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/daily_report_month_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_evidence.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';

void main() {
  DailyReportEvidenceRecord record(String path) => DailyReportEvidenceRecord(
    id: 'record',
    workerName: '',
    eventType: 'clock_in',
    confirmedAt: DateTime(2026, 10, 11),
    storagePath: path,
  );
  test(
    'ZIP keeps all same-date reports with safe unique Japanese names',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'daily-month-test-',
      );
      final entries = [
        for (var i = 0; i < 3; i++)
          DailyReportMonthEntry(
            id: 'same-prefix-$i',
            date: DateTime(2026, 10, 11),
            name: '../現場/写真',
            status: 'signed',
            siteId: 'site',
          ),
      ];
      var generated = 0;
      try {
        final zip = await DailyReportMonthZip.create(
          directory: directory,
          zipName: 'month.zip',
          entries: entries,
          checkActor: () {},
          build: (entry) async {
            generated++;
            return Uint8List.fromList([37, 80, 68, 70]);
          },
        );
        final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
        expect(generated, 3);
        expect(archive.files.length, 3);
        expect(archive.files.map((file) => file.name).toSet().length, 3);
        expect(
          archive.files.every(
            (file) => !file.name.contains('/') && file.name.contains('現場'),
          ),
          isTrue,
        );
        expect(File('${directory.path}/report.pdf').existsSync(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'failed report or changed actor never leaves shareable partial ZIP',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'daily-month-test-',
      );
      final entry = DailyReportMonthEntry(
        id: 'r',
        date: DateTime(2026, 10),
        name: '現場',
        status: 'signed',
      );
      try {
        await expectLater(
          DailyReportMonthZip.create(
            directory: directory,
            zipName: 'month.zip',
            entries: [entry, entry],
            checkActor: () {},
            build: (_) async => throw StateError('read failed'),
          ),
          throwsStateError,
        );
        expect(File('${directory.path}/month.zip').existsSync(), isFalse);
        var checks = 0;
        await expectLater(
          DailyReportMonthZip.create(
            directory: directory,
            zipName: 'month.zip',
            entries: [entry],
            checkActor: () {
              if (++checks > 2) throw StateError('actor changed');
            },
            build: (_) async => Uint8List.fromList([1]),
          ),
          throwsStateError,
        );
        expect(File('${directory.path}/month.zip').existsSync(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test('saved photo failure blocks whole month instead of partial export', () {
    expect(
      () => DailyReportMonthRepository.requireCompletePhotos([
        DailyReportPdfEvidence(
          record: record('saved.jpg'),
          downloadFailed: true,
        ),
      ]),
      throwsStateError,
    );
    expect(
      () => DailyReportMonthRepository.requireCompletePhotos([
        DailyReportPdfEvidence(record: record('saved.jpg')),
      ]),
      throwsStateError,
    );
  });
  test(
    'time-only evidence and successfully loaded photo remain exportable',
    () {
      expect(
        () => DailyReportMonthRepository.requireCompletePhotos([
          DailyReportPdfEvidence(record: record('')),
          DailyReportPdfEvidence(
            record: record('saved.jpg'),
            photoBytes: Uint8List.fromList([1]),
          ),
        ]),
        returnsNormally,
      );
    },
  );
  test('month boundaries include leap February and December rollover', () {
    expect(DailyReportMonthRepository.dateKey(DateTime(2024, 2)), '2024-02-01');
    expect(DailyReportMonthRepository.dateKey(DateTime(2024, 3)), '2024-03-01');
    expect(
      DailyReportMonthRepository.dateKey(DateTime(2026, 13)),
      '2027-01-01',
    );
  });
}

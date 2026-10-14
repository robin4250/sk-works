import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_history_file_decoder.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';

void main() {
  const text = '2026/10/14\n08:10\t投稿者\t10月14日\n現場A 山田\n現場A 定時';
  List<int> zip(List<ArchiveFile> entries) {
    final archive = Archive();
    for (final entry in entries) { archive.add(entry); }
    return ZipEncoder().encodeBytes(archive);
  }
  test('LINE ZIP ignores Mac resource text and parses October candidates', () {
    final bytes = zip([
      ArchiveFile.string('[LINE] 出勤簿.txt', text),
      ArchiveFile.bytes('__MACOSX/._[LINE] 出勤簿.txt', [0, 255, 128]),
    ]);
    final decoded = decodeLineHistoryFile(bytes, '出勤簿.ZIP');
    expect(decoded, text);
    final candidate = lineMonthlyCandidates(lineHistorySources(decoded), DateTime(2026, 10));
    expect(candidate.rows.single['work_date'], '2026-10-14');
  });
  test('plain UTF-8 text with BOM keeps the same source identities as ZIP', () {
    final decoded = decodeLineHistoryFile(utf8.encode('\uFEFF$text'), 'history.txt');
    final zipped = decodeLineHistoryFile(zip([ArchiveFile.string('nested/history.txt', text)]), 'history.zip');
    expect(lineHistorySources(decoded).map((source) => source['id']),
      lineHistorySources(zipped).map((source) => source['id']));
  });
  test('ambiguous or empty ZIP requires the original LINE file', () {
    expect(() => decodeLineHistoryFile(zip([
      ArchiveFile.string('one.txt', text), ArchiveFile.string('two.txt', text),
    ]), 'history.zip'), throwsFormatException);
    expect(() => decodeLineHistoryFile(zip([
      ArchiveFile.bytes('__MACOSX/._history.txt', [0, 255]),
    ]), 'history.zip'), throwsFormatException);
    expect(() => decodeLineHistoryFile([255, 255], 'history.txt'), throwsFormatException);
  });
  test('expanded text limit is enforced before reading a compressed member', () {
    final large = ArchiveFile.bytes('history.txt', List.filled(lineHistoryFileLimitBytes + 1, 65));
    expect(() => decodeLineHistoryFile(zip([large]), 'history.zip'), throwsFormatException);
  });
}

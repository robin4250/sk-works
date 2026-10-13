import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

import 'daily_report_month_repository.dart';

/// One PDF at a time; ZIP data streams to disk, never collecting a month's photos.
class DailyReportMonthZip {
  static String filename(DailyReportMonthEntry entry, int index) {
    final name = entry.name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'^\.+|\.+$'), '')
        .trim();
    final safeName = name.isEmpty
        ? '名称未取得'
        : String.fromCharCodes(name.runes.take(60));
    final id = entry.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final shortId = id.length > 12 ? id.substring(0, 12) : id;
    return '${DailyReportMonthRepository.dateKey(entry.date)}_${entry.siteId == null ? 'ルート' : '現場'}_${safeName}_${index.toString().padLeft(5, '0')}_$shortId.pdf';
  }

  static Future<File> create({
    required Directory directory,
    required String zipName,
    required List<DailyReportMonthEntry> entries,
    required Future<Uint8List> Function(DailyReportMonthEntry entry) build,
    required void Function() checkActor,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (entries.isEmpty) throw StateError('保存済み日報がありません。');
    final zip = File('${directory.path}/$zipName');
    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      checkActor();
      encoder.create(zip.path, level: 0);
      opened = true;
      for (var index = 0; index < entries.length; index++) {
        checkActor();
        final pdf = File('${directory.path}/report.pdf');
        {
          final bytes = await build(entries[index]);
          checkActor();
          if (bytes.isEmpty) throw StateError('日報PDFを生成できません。');
          await pdf.writeAsBytes(bytes, flush: true);
        }
        checkActor();
        await encoder.addFile(pdf, filename(entries[index], index + 1), 0);
        await pdf.delete();
        checkActor();
        onProgress?.call(index + 1, entries.length);
      }
      await encoder.close();
      opened = false;
      checkActor();
      return zip;
    } catch (_) {
      if (opened) {
        try {
          await encoder.close();
        } catch (_) {}
      }
      if (await zip.exists()) await zip.delete();
      rethrow;
    }
  }
}

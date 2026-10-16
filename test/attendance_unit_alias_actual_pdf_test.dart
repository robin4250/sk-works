import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/attendance/attendance_pdf_service.dart';
import 'package:sk_works/features/attendance/worker_attendance_sheet_repository.dart';

// A timer-free cache using the already adopted Japanese fixture font. Every
// unresolved key fails; this test never downloads a font or accepts Helvetica.
class _FixtureFontCache extends PdfBaseCache {
  _FixtureFontCache(this.bytes);
  final Uint8List bytes;
  final Set<String> resolved = {};
  @override
  Future<void> add(String key, Uint8List bytes) async => throw StateError('No font download');
  @override
  Future<Uint8List?> get(String key) async => bytes;
  @override
  Future<bool> contains(String key) async => true;
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<Uint8List> resolve({required String name, required Uri uri,
      bool cache = true, Map<String, String>? headers}) async {
    if (!{'NotoSansJP-Regular', 'NotoSansJP-Bold'}.contains(name)) {
      throw StateError('Unexpected font: $name');
    }
    resolved.add(name);
    return bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  final runtime = Platform.environment['RUNNER_TEMP'];
  test('actual attendance PDFs retain old units after SQL rename and retirement', () async {
    final output = Directory('${Platform.environment['SKO_PDF_OUTPUT_DIR']}/attendance-unit-alias')
      ..createSync(recursive: true);
    final fixture = File('${output.path}/rpc-maps.json');
    final generated = await Process.run('node', [
      'tool/export_attendance_unit_alias_fixture.mjs',
      '$runtime/sko-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js',
      fixture.path,
    ]);
    expect(generated.exitCode, 0, reason: '${generated.stdout}\n${generated.stderr}');
    final maps = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
    final oldCache = PdfBaseCache.defaultCache;
    final fonts = _FixtureFontCache(File(fontPath!).readAsBytesSync());
    PdfBaseCache.defaultCache = fonts;
    try {
      for (final phase in ['before', 'renamed', 'retired']) {
        final units = Map<String, String>.from(maps[phase] as Map);
        final date = DateTime(2026, 10, 1);
        final data = WorkerAttendanceMonth(year: 2026, month: 10,
          allowanceUnits: units, days: {
            date: WorkerAttendanceDay(date: date, siteName: '隔離検証現場',
              manDays: 1, allowanceNames: const ['足場手当', '安全手当'],
              allowanceUnits: units),
          });
        File('${output.path}/attendance_units_month_$phase.pdf').writeAsBytesSync(
          await AttendancePdfService.buildPdf(DateTime(2026, 10), data,
            workerName: '検証社員'));
        File('${output.path}/attendance_units_workers_$phase.pdf').writeAsBytesSync(
          await AttendancePdfService.buildWorkersPdf(DateTime(2026, 10),
            [(workerName: '検証社員', data: data)]));
      }
      expect(fonts.resolved, {'NotoSansJP-Regular', 'NotoSansJP-Bold'});
      final inspected = await Process.run('python', [
        'tool/verify_attendance_unit_alias_pdf.py', output.path,
      ]);
      expect(inspected.exitCode, 0, reason: '${inspected.stdout}\n${inspected.stderr}');
      final report = jsonDecode(inspected.stdout.toString()) as Map<String, dynamic>;
      expect(report, hasLength(6));
      File('${output.path}/inspection.json').writeAsStringSync(inspected.stdout.toString());
    } finally {
      PdfBaseCache.defaultCache = oldCache;
    }
  }, skip: fontPath == null || runtime == null
      ? 'Requires the existing Flutter CI Japanese-font/PGlite/PyMuPDF setup.' : false,
    timeout: const Timeout(Duration(minutes: 3)));
}

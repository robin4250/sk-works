import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/help/manual_pdf_service.dart';
import 'package:sk_works/features/help/manual_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontPath = Platform.environment['SKO_PDF_FONT_PATH'];
  final hasFont = fontPath != null && File(fontPath).existsSync();
  test('all beta manuals render complete Japanese sections on A4 pages', () async {
    final font = pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
    final output = Platform.environment['SKO_PDF_OUTPUT_DIR'] ??
        (await Directory.systemTemp.createTemp('sko-manual-pdfs-')).path;
    await Directory(output).create(recursive: true);
    final cases = <String, List<ManualSection>>{
      'general': ManualContent.forRole(ManualRole.general),
      'sub_admin': ManualContent.forRole(ManualRole.subAdmin),
      'admin': ManualContent.forRole(ManualRole.admin),
      'pamphlet': ManualContent.pamphlet,
    };
    final roles = <String, ManualRole>{
      'general': ManualRole.general,
      'sub_admin': ManualRole.subAdmin,
      'admin': ManualRole.admin,
    };
    String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
    for (final entry in cases.entries) {
      final bytes = entry.key == 'pamphlet'
          ? await ManualPdfService.buildPamphlet(regularFont: font, boldFont: font)
          : await ManualPdfService.buildRoleManual(roles[entry.key]!, regularFont: font, boldFont: font);
      final file = File('$output/manual_beta_${entry.key}.pdf');
      await file.writeAsBytes(bytes);
      final result = await Process.run('python', ['-c', r'''
import fitz,json,sys
pdf=fitz.open(sys.argv[1])
print(json.dumps([{'width':p.rect.width,'height':p.rect.height,'text':p.get_text(),'links':len(p.get_links()),'spans':[{'text':s['text'],'bbox':s['bbox']} for b in p.get_text('dict')['blocks'] for l in b.get('lines',[]) for s in l['spans']]} for p in pdf],ensure_ascii=False))
''', file.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final pages = (jsonDecode(result.stdout.toString()) as List<dynamic>).cast<Map<String, dynamic>>();
      expect(pages.length, greaterThan(entry.value.length));
      final allText = normalize(pages.map((page) => page['text']).join(' '));
      expect(pages.fold<int>(0, (count, page) => count + (page['links'] as int)),
        greaterThanOrEqualTo(entry.value.length * 2));
      for (final section in entry.value) {
        for (final expected in [section.title, section.summary,
          section.buttonLabel, section.support, ...section.steps]) {
          expect(allText, contains(normalize(expected)),
            reason: '${entry.key} omitted registered feature content.');
        }
      }
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index];
        expect(page['width'] as num, closeTo(595.2756, .02));
        expect(page['height'] as num, closeTo(841.8898, .02));
        final text = normalize(page['text'] as String);
        for (final expected in [ManualVersion.label, 'ベータ版', '${index + 1} / ${pages.length}']) {
          expect(text, contains(normalize(expected)));
        }
        for (final span in (page['spans'] as List<dynamic>).cast<Map<String, dynamic>>()) {
          final box = (span['bbox'] as List<dynamic>).cast<num>();
          expect(box[0], greaterThanOrEqualTo(35));
          expect(box[1], greaterThanOrEqualTo(35));
          expect(box[2], lessThanOrEqualTo(560.3));
          expect(box[3], lessThanOrEqualTo(806.9), reason: '${entry.key} page ${index + 1} text escapes the printable A4 area: ${span['text']}');
        }
      }
    }
    final longChapter = ManualSection(
      title: '長い機能の説明', summary: '必要な手順を途中で削りません。',
      buttonLabel: '確認する',
      steps: List.generate(100, (i) => '手順$i：対象を確認して保存後の表示を確認します。'),
      support: '最後の補足も確認できます。',
    );
    final chapter = File('$output/manual_beta_long_chapter.pdf');
    await chapter.writeAsBytes(await ManualPdfService.buildChapter(longChapter,
      regularFont: font, boldFont: font));
    final inspection = await Process.run('python', ['-c',
      'import fitz,json,sys; p=fitz.open(sys.argv[1]); print(json.dumps({"pages":len(p),"text":"".join(x.get_text() for x in p),"links":sum(len(x.get_links()) for x in p)},ensure_ascii=False))',
      chapter.path]);
    expect(inspection.exitCode, 0, reason: inspection.stderr.toString());
    final detail = jsonDecode(inspection.stdout.toString()) as Map<String, dynamic>;
    expect(detail['pages'] as int, greaterThan(2));
    expect(detail['links'] as int, greaterThanOrEqualTo(2));
    for (final step in longChapter.steps) {
      expect(normalize(detail['text'] as String), contains(normalize(step)));
    }
    expect(normalize(detail['text'] as String), contains(normalize(longChapter.support)));
  }, skip: !hasFont ? 'Set SKO_PDF_FONT_PATH for actual Japanese PDF generation.' : false);
}


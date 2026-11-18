import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/personal_vault/retirement_pdf_renderer.dart';
import 'package:sk_works/features/personal_vault/retirement_render_envelope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final input = Platform.environment['SKO_RETIREMENT_RENDER_INPUT'];
    final output = Platform.environment['SKO_RETIREMENT_RENDER_OUTPUT'];
    if (input == null || output == null) exit(64);
    final dir = File(input).parent;
    if (File(output).parent.path != dir.path ||
        await FileSystemEntity.type(output, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await File(input).length() > 1048576) {
      exit(64);
    }
    final envelope = jsonDecode(await File(input).readAsString()) as Map;
    final regular = await rootBundle.load('assets/fonts/web-ui/NotoSansJP-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/company-seal/NotoSansJP-Bold.ttf');
    final pdf = await renderRetirementEnvelope(envelope, RetirementPdfRenderer(
      regularFont: pw.Font.ttf(regular),
      boldFont: pw.Font.ttf(bold),
    ));
    if (pdf.length > 6291456) exit(65);
    await File(output).create(exclusive: true);
    await File(output).writeAsBytes(pdf, flush: true);
    exit(0);
  } catch (_) {
    exit(65);
  }
}

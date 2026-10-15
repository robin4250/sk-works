import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/company_seal_snapshot.dart';
import '../shared/company_seal_pdf.dart';

/// Reuses the official seal renderer. The temporary page contains only the seal,
/// never a contract document, approval or fabricated signature.
Future<Uint8List> renderSiteContractSeal(CompanySealSnapshot snapshot, String companyId) async {
  if (snapshot.name.isEmpty) {
    throw StateError('登録された会社印がありません。');
  }
  if (snapshot.style == CompanySealPdf.reishoStyle &&
      (await CompanySealPdf.unsupportedReishoCharacters(snapshot.name)).isNotEmpty) {
    throw StateError('登録された会社印を正しく表示できません。');
  }
  final font = await CompanySealPdf.loadStyleFont(snapshot.style);
  final document = pw.Document();
  document.addPage(pw.Page(pageFormat: const PdfPageFormat(120, 120),
    margin: const pw.EdgeInsets.all(12), build: (_) => pw.Center(
      child: CompanySealPdf.build(snapshot.name, size: 80, font: font,
        style: snapshot.style, companyId: companyId),
    )));
  final bytes = await document.save();
  final raster = await Printing.raster(bytes, pages: const [0], dpi: 160).first;
  return raster.toPng();
}

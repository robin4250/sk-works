import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../../domain/company_seal_image_processing.dart';
import '../../domain/company_uploaded_seal_png.dart';

enum SealImportKind { camera, gallery, file }
class SealImportInput {
  SealImportInput({required this.name, required Uint8List bytes, this.isPdf = false})
      : _bytes = Uint8List.fromList(bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) { throw const FormatException('読込ファイルは20MB以下にしてください。'); }
    if (isPdf && (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-')) {
      throw const FormatException('PDFファイルを確認してください。');
    }
  }
  static const maxBytes = 20 * 1024 * 1024;
  final String name;
  final bool isPdf;
  final Uint8List _bytes;
  Uint8List get bytes => _bytes.asUnmodifiableView();
}
class SealImportFrame {
  SealImportFrame({required this.image, required Uint8List previewPng})
      : _previewPng = Uint8List.fromList(previewPng);
  final SealRgbaImage image;
  final Uint8List _previewPng;
  Uint8List get previewPng => _previewPng.asUnmodifiableView();
}

Future<SealImportInput?> pickCompanySealInput(SealImportKind kind) async {
  if (kind == SealImportKind.file) {
    final file = await FilePicker.pickFile(type: FileType.custom,
        allowedExtensions: const ['png','jpg','jpeg','heic','heif','pdf']);
    if (file == null) { return null; }
    final size = await file.length();
    if (size != null && size > SealImportInput.maxBytes) { throw const FormatException('読込ファイルは20MB以下にしてください。'); }
    return SealImportInput(name:file.name,bytes:Uint8List.fromList(await file.readAsBytes()),
        isPdf:file.extension?.toLowerCase() == 'pdf');
  }
  // The platform produces a bounded working copy; the original gallery asset
  // is never overwritten. iOS HEIC/HEIF is decoded/re-encoded by image_picker.
  final file = await ImagePicker().pickImage(source:kind == SealImportKind.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth:2048,maxHeight:2048,imageQuality:100,requestFullMetadata:false);
  if (file == null) { return null; }
  if (await file.length() > SealImportInput.maxBytes) { throw const FormatException('読込ファイルは20MB以下にしてください。'); }
  return SealImportInput(name:file.name,bytes:await file.readAsBytes());
}

class CompanySealImageImport {
  static const maxPdfPages = 20;
  static Future<SealImportFrame> decode(SealImportInput input, {int pdfPage = 0}) async {
    Uint8List encoded = input.bytes;
    if (input.isPdf) {
      if (pdfPage < 0 || pdfPage >= maxPdfPages) { throw const FormatException('PDFは1〜20ページ目から選んでください。'); }
      try {
        final raster = await Printing.raster(input.bytes,pages:[pdfPage],dpi:144).first.timeout(const Duration(seconds:20));
        if (raster.width > 4096 || raster.height > 4096 || raster.width * raster.height > 16 * 1024 * 1024) {
          throw const FormatException('PDFの用紙が大きすぎます。角印のある通常サイズのページを選んでください。');
        }
        encoded = await raster.toPng();
      } on FormatException { rethrow; }
      catch (_) { throw const FormatException('このPDFページを読み込めません。ページ番号かファイルを確認してください。'); }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width < 32 || descriptor.height < 32 || descriptor.width > 8192 || descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 32 * 1024 * 1024) {
        throw const FormatException('32px以上・3200万画素以下の写真を選んでください。');
      }
      final largest = descriptor.width > descriptor.height ? descriptor.width : descriptor.height;
      final ratio = largest > SealRgbaImage.maxDimension ? SealRgbaImage.maxDimension / largest : 1.0;
      codec = await descriptor.instantiateCodec(targetWidth:(descriptor.width * ratio).round(),targetHeight:(descriptor.height * ratio).round());
      if (codec.frameCount != 1) { throw const FormatException('静止画を選んでください。'); }
      image = (await codec.getNextFrame()).image;
      final rgba = await image.toByteData(format:ui.ImageByteFormat.rawStraightRgba);
      final preview = await image.toByteData(format:ui.ImageByteFormat.png);
      if (rgba == null || preview == null) { throw const FormatException('写真の画像データを読み込めません。'); }
      return SealImportFrame(image:SealRgbaImage(width:image.width,height:image.height,
          pixels:rgba.buffer.asUint8List(rgba.offsetInBytes,rgba.lengthInBytes)),
          previewPng:preview.buffer.asUint8List(preview.offsetInBytes,preview.lengthInBytes));
    } on FormatException { rethrow; }
    catch (_) { throw const FormatException('この環境で画像を読めません。JPEG・PNGか、iPhoneの「写真から選ぶ」を使ってください。'); }
    finally { image?.dispose(); codec?.dispose(); descriptor?.dispose(); buffer.dispose(); }
  }
  static Future<Uint8List> encode(SealRgbaImage frame) async {
    // ImageDescriptor.raw consumes premultiplied RGBA. The processing model is
    // straight RGBA so alpha must be applied exactly once at this boundary.
    final rgba = Uint8List.fromList(frame.pixels);
    for (var index = 0; index < rgba.length; index += 4) {
      final alpha = rgba[index + 3];
      for (var channel = 0; channel < 3; channel++) {
        rgba[index + channel] = (rgba[index + channel] * alpha / 255).round();
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(buffer,width:frame.width,height:frame.height,
        rowBytes:frame.width*4,pixelFormat:ui.PixelFormat.rgba8888);
    ui.Codec? codec; ui.Image? image;
    try {
      codec = await descriptor.instantiateCodec(); image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format:ui.ImageByteFormat.png);
      if (data == null) { throw const FormatException('PNGを生成できません。'); }
      return data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes);
    } finally { image?.dispose(); codec?.dispose(); descriptor.dispose(); buffer.dispose(); }
  }
  static Future<CompanyUploadedSealPng> prepare(SealRgbaImage frame, SealPixelCrop crop,
      {SealImageOptions options = const SealImageOptions()}) async {
    final processed = await compute(_prepare, (frame,crop,options));
    return CompanyUploadedSealPng.fromBytes(await encode(processed));
  }
  static SealRgbaImage _prepare((SealRgbaImage,SealPixelCrop,SealImageOptions) request) =>
      prepareCompanySealImage(request.$1,request.$2,options:request.$3);
}

// Internal RAM preview subprocess. Input must be an authenticated server's
// unsigned-review envelope. Output is not an approved or sendable original.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Reuses app source in the standalone renderer package.
// ignore: avoid_relative_lib_imports
import '../lib/features/shared/company_pdf_assets_io.dart';
// ignore: avoid_relative_lib_imports
import '../lib/features/sites/site_order_outgoing_consent_preview.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw StateError('Asset root required.');
    }
    configureCanonicalPdfAssets(arguments.single);
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stdin) {
      if (buffer.length + chunk.length > 2 * 1024 * 1024) {
        throw StateError('Preview evidence too large.');
      }
      buffer.add(chunk);
    }
    final raw = jsonDecode(utf8.decode(buffer.takeBytes()));
    if (raw is! Map) {
      throw const FormatException('Preview envelope required.');
    }
    final preview = SiteOrderOutgoingConsentPreview.fromServerEnvelope(
        Map<String, dynamic>.from(raw));
    final bytes = await preview.render();
    if (bytes.length > 20 * 1024 * 1024) {
      throw StateError('Preview PDF too large.');
    }
    stdout.add(bytes);
    await stdout.flush();
  } catch (_) {
    // Never log document bodies, people, stamp bytes or filesystem paths.
    stderr.writeln('unsigned_preview_render_rejected');
    exitCode = 1;
  }
}

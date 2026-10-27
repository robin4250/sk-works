// Offline candidate: runtime dependencies must be pinned and installed by the
// trusted service. File parsing is resource-intensive and must run in an
// isolated worker with memory, CPU, and wall-clock limits imposed externally.
export function createDocumentFileValidator({ sharp, pdfjs }) {
  if (typeof sharp !== 'function' || typeof pdfjs?.getDocument !== 'function') throw Error('validator_unavailable');
  return async function validateFile({ bytes, mime }) {
    if (!(bytes instanceof Uint8Array) || bytes.length < 8 || bytes.length > 20 * 1024 * 1024) return false;
    if (mime === 'application/pdf') {
      let task;
      try {
        task = pdfjs.getDocument({ data: Uint8Array.from(bytes), stopAtErrors: true, isEvalSupported: false, disableFontFace: true, useSystemFonts: false });
        const doc = await task.promise;
        if (!Number.isSafeInteger(doc.numPages) || doc.numPages < 1 || doc.numPages > 100) return false;
        for (let i = 1; i <= doc.numPages; i++) {
          const page = await doc.getPage(i);
          const viewport = page.getViewport({ scale: 1 });
          if (!Number.isFinite(viewport.width) || !Number.isFinite(viewport.height) || viewport.width <= 0 || viewport.height <= 0 || viewport.width > 20000 || viewport.height > 20000) return false;
          await page.getOperatorList();
          page.cleanup();
        }
        return true;
      } catch (_) { return false; }
      finally { if (task) await task.destroy().catch(() => {}); }
    }
    const expected = { 'image/jpeg': 'jpeg', 'image/png': 'png', 'image/heic': 'heif' }[mime];
    if (!expected) return false;
    try {
      const input = sharp(Buffer.from(bytes), { failOn: 'warning', limitInputPixels: 40000000, sequentialRead: true, animated: false });
      const metadata = await input.metadata();
      if (metadata.format !== expected || !metadata.width || !metadata.height || (metadata.pages ?? 1) !== 1) return false;
      // Decode the entire image, not only its header. Output is discarded.
      await input.raw().toBuffer();
      return true;
    } catch (_) { return false; }
  };
}

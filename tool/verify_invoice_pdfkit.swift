// Verify Apple's parser and renderer with the actual adopted invoice PDFs.
// iOS CI separately compiles the UIKit PDFView platform-view implementation.
import Foundation
import PDFKit
import AppKit

for path in CommandLine.arguments.dropFirst() {
  guard let document = PDFDocument(url: URL(fileURLWithPath: path)), document.pageCount > 0 else {
    fatalError("Invoice PDF could not be opened: \(path)")
  }
  for index in 0..<document.pageCount {
    guard let page = document.page(at: index) else { fatalError("Missing invoice page") }
    let image = page.thumbnail(of: NSSize(width: 300, height: 424), for: .mediaBox)
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
      fatalError("PDFKit did not draw invoice page")
    }
    var markedPixels = 0
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.alphaComponent > 0.1 && min(color.redComponent, min(color.greenComponent, color.blueComponent)) < 0.95 {
          markedPixels += 1
        }
      }
    }
    precondition(markedPixels > 100, "PDFKit invoice page was blank")
  }
  print("PDFKit invoice pages verified: \(document.pageCount)")
}

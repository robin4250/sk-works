#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_ios_app_icon.swift OUTPUT_PNG\n", stderr)
    exit(2)
}

let output = CommandLine.arguments[1]
let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let top = NSColor(calibratedRed: 0.06, green: 0.52, blue: 0.89, alpha: 1).cgColor
let bottom = NSColor(calibratedRed: 0.02, green: 0.38, blue: 0.74, alpha: 1).cgColor
guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [top, bottom] as CFArray,
    locations: [0.0, 1.0]
) else {
    fputs("failed to create gradient\n", stderr)
    exit(1)
}

context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 512, y: 1024),
    end: CGPoint(x: 512, y: 0),
    options: []
)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let font =
    NSFont(name: "HelveticaNeue-BoldItalic", size: 330)
    ?? NSFont(name: "Arial-BoldItalicMT", size: 330)
    ?? NSFont.boldSystemFont(ofSize: 330)

let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]

let logo = "SKO" as NSString
let measured = logo.size(withAttributes: attributes)
let rect = NSRect(
    x: 0,
    y: (canvas.height - measured.height) / 2 + 20,
    width: canvas.width,
    height: measured.height
)
logo.draw(in: rect, withAttributes: attributes)
image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: output))

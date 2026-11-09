#!/usr/bin/env swift
// Renders the app icon (D-icon-script): the menu-bar ring glyph on a rounded rectangle, every macOS size,
// into Sources/TokenBeApp/Resources/Assets.xcassets/AppIcon.appiconset. Run once; the PNGs are committed.
//   swift scripts/make-icon.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Sources/TokenBeApp/Resources/Assets.xcassets/AppIcon.appiconset")

/// (point size, scale) pairs required by a macOS app icon set.
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

func render(pixels: Int) -> Data? {
  let side = CGFloat(pixels)
  guard let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else { return nil }
  // Rounded rectangle inset like Apple's icon grid (~10 % margin, ~22 % corner radius).
  let inset = side * 0.1
  let tile = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
  let radius = tile.width * 0.225
  context.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
  let top = CGColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x20 / 255, alpha: 1)
  let bottom = CGColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x18 / 255, alpha: 1)
  context.saveGState()
  context.clip()
  if let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1]) {
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
  }
  context.restoreGState()
  // The ring: accent blue (08 dark accent #3B82F6), stroke ≈ 1.5/18 of the glyph size as in the menu bar.
  let ringSide = tile.width * 0.56
  let ring = CGRect(x: side / 2 - ringSide / 2, y: side / 2 - ringSide / 2, width: ringSide, height: ringSide)
  context.setStrokeColor(CGColor(srgbRed: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1))
  context.setLineWidth(max(1, ringSide * 1.5 / 14))
  context.strokeEllipse(in: ring)
  guard let image = context.makeImage() else { return nil }
  return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

do {
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  var images: [[String: String]] = []
  for (points, scale) in slots {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    guard let png = render(pixels: points * scale) else {
      FileHandle.standardError.write(Data("make-icon: could not render \(name)\n".utf8))
      exit(1)
    }
    try png.write(to: output.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
  }
  let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
  let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
  try json.write(to: output.appendingPathComponent("Contents.json"))
  FileHandle.standardOutput.write(Data("make-icon: wrote \(slots.count) images to \(output.path)\n".utf8))
} catch {
  FileHandle.standardError.write(Data("make-icon: \(error)\n".utf8))
  exit(1)
}

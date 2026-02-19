#!/usr/bin/env swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = "Linnet/Resources/Assets.xcassets/AppIcon.appiconset"

// Ensure output directory exists
let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.2
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient: teal to blue (matching AccentColor)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.0, green: 0.75, blue: 0.78, alpha: 1.0),
        NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    // Music note symbol
    let fontSize = s * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .light)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let note = "\u{266A}"
    let noteSize = note.size(withAttributes: attrs)
    let noteOrigin = NSPoint(
        x: (s - noteSize.width) / 2,
        y: (s - noteSize.height) / 2
    )
    note.draw(at: noteOrigin, withAttributes: attrs)

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate icon at size \(size)")
        continue
    }

    let filePath = "\(outputDir)/icon_\(size)x\(size).png"
    try! png.write(to: URL(fileURLWithPath: filePath))
    print("Generated \(filePath)")
}
print("Done: generated \(sizes.count) icon files")

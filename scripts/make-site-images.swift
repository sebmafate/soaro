// Makes the images of the website that are not screenshots: favicons, app icons and the social cards.
//
// Usage: swift scripts/make-site-images.swift
// Needs: assets/icon.svg, site/screenshots/en-overview-dark.webp and fr-overview-dark.webp (see scripts/make-screenshots.sh).
// Writes into site/. The icon artwork itself is never changed.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let site = root.appendingPathComponent("site")
let iconURL = root.appendingPathComponent("assets/icon.svg")

func bitmap(_ width: Int, _ height: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(_ rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    let url = site.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(name) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

/// The icon, with transparent rounded corners (as in assets/icon.svg).
let icon = NSImage(contentsOf: iconURL)!

/// A full-bleed square version (no transparent corners), for places that round the icon themselves.
let squareIcon: NSImage = {
    let svg = try! String(contentsOf: iconURL, encoding: .utf8).replacingOccurrences(of: "rx=\"230\"", with: "rx=\"0\"")
    return NSImage(data: Data(svg.utf8))!
}()

func renderIcon(_ image: NSImage, size: Int, name: String) {
    let rep = bitmap(size, size)
    draw(rep) { image.draw(in: NSRect(x: 0, y: 0, width: size, height: size)) }
    save(rep, name)
}

// MARK: Icons

renderIcon(icon, size: 32, name: "favicon-32.png")

// favicon.ico: three PNG images (16, 32 and 48 px) in one file, for old browsers and for tools that ask for /favicon.ico.
func png(_ image: NSImage, size: Int) -> Data {
    let rep = bitmap(size, size)
    draw(rep) { image.draw(in: NSRect(x: 0, y: 0, width: size, height: size)) }
    return rep.representation(using: .png, properties: [:])!
}
func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
let icoSizes = [16, 32, 48]
let icoImages = icoSizes.map { png(icon, size: $0) }
var ico = le(UInt16(0)) + le(UInt16(1)) + le(UInt16(icoSizes.count))
var offset = 6 + 16 * icoSizes.count
for (size, data) in zip(icoSizes, icoImages) {
    ico += Data([UInt8(size), UInt8(size), 0, 0]) + le(UInt16(1)) + le(UInt16(32)) + le(UInt32(data.count)) + le(UInt32(offset))
    offset += data.count
}
for data in icoImages { ico += data }
try! ico.write(to: site.appendingPathComponent("favicon.ico"))
print("wrote favicon.ico")
renderIcon(squareIcon, size: 180, name: "apple-touch-icon.png")       // iOS rounds the corners itself
renderIcon(icon, size: 192, name: "icon-192.png")
renderIcon(icon, size: 512, name: "icon-512.png")
renderIcon(squareIcon, size: 512, name: "icon-512-maskable.png")      // the waves stay inside the safe zone

// MARK: Social cards (1200 x 630)

struct Card {
    var file: String
    var screenshot: String
    var headline: String
    var subtitle: String
    var footer: String
}

let cards = [
    Card(file: "og-en.png", screenshot: "en-overview-dark.webp", headline: "A lighter Mac.",
         subtitle: "Menu bar monitor and cleaner for macOS", footer: "soaro.app  ·  Free and open source"),
    Card(file: "og-fr.png", screenshot: "fr-overview-dark.webp", headline: "Un Mac plus léger.",
         subtitle: "Moniteur et nettoyeur pour la barre de menus du Mac", footer: "soaro.app  ·  Gratuit et open source"),
]

func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint, width: CGFloat) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.lineSpacing = 2
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let bounds = attributed.boundingRect(with: NSSize(width: width, height: 1_000), options: [.usesLineFragmentOrigin])
    // `point.y` is the top of the text block (flipped by hand, Core Graphics origin is bottom left).
    attributed.draw(with: NSRect(x: point.x, y: point.y - bounds.height, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
    return bounds.height
}

for card in cards {
    let width = 1200, height = 630
    let rep = bitmap(width, height)
    guard let shot = NSImage(contentsOf: site.appendingPathComponent("screenshots/\(card.screenshot)")) else {
        print("missing screenshot \(card.screenshot)"); continue
    }
    draw(rep) {
        // Background: the colors of the icon.
        let gradient = NSGradient(starting: NSColor(srgbRed: 0x16 / 255, green: 0x39 / 255, blue: 0x5C / 255, alpha: 1),
                                  ending: NSColor(srgbRed: 0x1F / 255, green: 0x8F / 255, blue: 0x8C / 255, alpha: 1))!
        gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -35)

        // Screenshot on the right, rounded, with a shadow, bleeding off the bottom right corner.
        let shotWidth: CGFloat = 690
        let shotHeight = shotWidth * shot.size.height / shot.size.width
        let shotRect = NSRect(x: 530, y: CGFloat(height) - 78 - shotHeight, width: shotWidth, height: shotHeight)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: shotRect, xRadius: 22, yRadius: 22).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: shotRect, xRadius: 22, yRadius: 22).addClip()
        shot.draw(in: shotRect)
        NSGraphicsContext.restoreGraphicsState()

        // Left column.
        icon.draw(in: NSRect(x: 72, y: CGFloat(height) - 72 - 104, width: 104, height: 104))
        var top = CGFloat(height) - 72 - 104 - 40
        top -= text(card.headline, size: 68, weight: .bold, color: .white, at: NSPoint(x: 72, y: top), width: 440) + 18
        _ = text(card.subtitle, size: 28, weight: .regular, color: NSColor.white.withAlphaComponent(0.88), at: NSPoint(x: 72, y: top), width: 420)
        _ = text(card.footer, size: 22, weight: .medium, color: NSColor.white.withAlphaComponent(0.75), at: NSPoint(x: 72, y: 72), width: 440)
    }
    save(rep, card.file)
}

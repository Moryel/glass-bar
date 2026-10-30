import AppKit
// SF Symbols'ü beyaz, saydam zeminli PNG olarak çıkarır (CSS mask için).
let adlar = CommandLine.arguments.dropFirst()
for ad in adlar {
    guard let s = NSImage(systemSymbolName: ad, accessibilityDescription: nil) else { print("YOK \(ad)"); continue }
    let cfg = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium).applying(.init(paletteColors: [.white]))
    let img = s.withSymbolConfiguration(cfg)!
    let sz = img.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sz.width.rounded(.up)) , pixelsHigh: Int(sz.height.rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(origin: .zero, size: sz))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "simgeler/\(ad).png"))
    print("ok \(ad) \(Int(sz.width))x\(Int(sz.height))")
}

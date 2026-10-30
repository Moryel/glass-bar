import AppKit
// Uygulama ikonlarını paket kimliğinden 64 px PNG olarak çıkarır.
for kimlik in CommandLine.arguments.dropFirst() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: kimlik) else { print("YOK \(kimlik)"); continue }
    let ikon = NSWorkspace.shared.icon(forFile: url.path)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    ikon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "ikonlar/\(kimlik).png"))
    print("ok \(kimlik) \(url.lastPathComponent)")
}

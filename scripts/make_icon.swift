import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let background = NSBezierPath(rect: rect)
    NSGradient(starting: NSColor(red: 0.08, green: 0.20, blue: 0.23, alpha: 1),
               ending: NSColor(red: 0.08, green: 0.47, blue: 0.44, alpha: 1))!.draw(in: background, angle: -35)

    let accent = NSColor(red: 0.68, green: 0.94, blue: 0.82, alpha: 1)
    let path = NSBezierPath()
    path.lineWidth = 64
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: 255, y: 425))
    path.line(to: NSPoint(x: 415, y: 565))
    path.line(to: NSPoint(x: 550, y: 485))
    path.line(to: NSPoint(x: 770, y: 690))
    accent.setStroke()
    path.stroke()

    for (x, height) in [(260.0, 105.0), (450.0, 160.0), (640.0, 225.0)] {
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 230, width: 92, height: height), xRadius: 45, yRadius: 45)
        NSColor.white.withAlphaComponent(0.92).setFill()
        bar.fill()
    }
    return true
}
let output = CommandLine.arguments[1]
let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

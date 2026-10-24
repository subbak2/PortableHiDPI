import AppKit
import QuartzCore

/// Draws a copy of the cursor where macOS fails to show it while mirroring.
///
/// The panel mirrors the virtual display but keeps its own, smaller desktop area (e.g. 1280×800
/// points for a 2560×1600 panel vs 1680×1050 for the virtual display, same origin). The arrow is
/// drawn fine everywhere, but cursors set by apps (link hand, I-beam…) vanish in the strip that is
/// inside the virtual display and outside the panel's area: the right and bottom ~24%.
/// There, if the current cursor is not the arrow, we show its image in click-through windows.
///
/// The windows stay put over the strip and only a layer moves inside them: moving a layer is
/// composited by the GPU at the display's refresh rate, moving a window is a window-server round
/// trip per mouse event (choppy and CPU-heavy).
final class CursorOverlay {
    private let virtualID: CGDirectDisplayID
    private let panelID: CGDirectDisplayID
    private var monitor: Any?
    private var screenObserver: Any?
    private var timer: Timer?  // only while the pointer is in the strip, to catch shape changes without movement
    private var strips: [(window: NSWindow, layer: CALayer)] = []
    private var shape: (size: NSSize, hotSpot: NSPoint)?
    private var shown = false
    private var lastShapeCheck = Date.distantPast
    private let arrow = NSCursor.arrow
    /// System Settings › Accessibility › Display › Pointer size (1.0 = default). NSCursor images are
    /// always default size, so the copy is scaled to match what the user sees elsewhere.
    private var pointerScale = CursorOverlay.readPointerScale()

    init(virtualID: CGDirectDisplayID, panelID: CGDirectDisplayID) {
        self.virtualID = virtualID
        self.panelID = panelID
    }

    func start() {
        guard monitor == nil else { return }
        buildStrips()
        // Mouse-move monitoring of other apps needs no Accessibility permission.
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in self?.update() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.buildStrips() }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        monitor = nil
        screenObserver = nil
        timer?.invalidate()
        timer = nil
        strips.forEach { $0.window.orderOut(nil) }
        strips = []
    }

    /// Re-reads the pointer size, e.g. after the user changed it in System Settings.
    func syncPointerSize() {
        pointerScale = Self.readPointerScale()
        shape = nil
    }

    // MARK: - Strip windows

    /// The L-shaped area inside the virtual display but outside the panel, as two rectangles
    /// in Cocoa coordinates: the strip right of the panel and the strip below it.
    private func stripRects() -> [NSRect] {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        func cocoa(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height) }
        let v = cocoa(CGDisplayBounds(virtualID)), p = cocoa(CGDisplayBounds(panelID))
        guard v.width > 0, p.width > 0 else { return [] }
        let right = NSRect(x: p.maxX, y: v.minY, width: v.maxX - p.maxX, height: v.height)
        let below = NSRect(x: v.minX, y: v.minY, width: p.maxX - v.minX, height: p.minY - v.minY)
        return [right, below].filter { $0.width > 0 && $0.height > 0 }
    }

    private func buildStrips() {
        strips.forEach { $0.window.orderOut(nil) }
        strips = stripRects().map { rect in
            let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
            view.wantsLayer = true
            let layer = CALayer()
            layer.contentsGravity = .resize
            layer.isHidden = true
            view.layer?.addSublayer(layer)
            window.contentView = view
            return (window, layer)
        }
        shape = nil
        shown = false
    }

    // MARK: - Tracking

    private func update() {
        let point = NSEvent.mouseLocation
        guard strips.contains(where: { $0.window.frame.contains(point) }) else {
            timer?.invalidate()
            timer = nil
            shape = nil
            return hide()
        }
        if timer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.lastShapeCheck = .distantPast
                self?.update()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        // Shape checks (a window-server round trip) are limited to every 0.1 s to keep CPU low.
        if Date().timeIntervalSince(lastShapeCheck) > 0.1 {
            lastShapeCheck = Date()
            refreshShape()
        }
        guard let shape else { return hide() }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for strip in strips {
            let f = strip.window.frame
            strip.layer.frame = NSRect(x: point.x - shape.hotSpot.x - f.minX,
                                       y: point.y - (shape.size.height - shape.hotSpot.y) - f.minY,
                                       width: shape.size.width, height: shape.size.height)
            strip.layer.isHidden = false
        }
        CATransaction.commit()
        if !shown {
            strips.forEach { $0.window.orderFrontRegardless() }
            shown = true
        }
    }

    private func hide() {
        guard shown else { return }
        strips.forEach { $0.window.orderOut(nil) }
        shown = false
    }

    private func refreshShape() {
        guard let cursor = NSCursor.currentSystem, !isArrow(cursor) else {
            shape = nil
            return
        }
        let size = NSSize(width: cursor.image.size.width * pointerScale, height: cursor.image.size.height * pointerScale)
        let hotSpot = NSPoint(x: cursor.hotSpot.x * pointerScale, y: cursor.hotSpot.y * pointerScale)
        if shape?.size != size || shape?.hotSpot != hotSpot {
            var rect = NSRect(origin: .zero, size: size)
            let image = cursor.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            for strip in strips {
                strip.layer.contents = image
                strip.layer.contentsScale = strip.window.backingScaleFactor
            }
        }
        shape = (size, hotSpot)
    }

    /// The arrow is still drawn by macOS in that strip, so don't draw a second one.
    /// Compared by shape ratios, not pixels, so it still matches when Pointer Size is enlarged.
    private func isArrow(_ cursor: NSCursor) -> Bool {
        func ratios(_ c: NSCursor) -> (Double, Double, Double) {
            let s = c.image.size
            guard s.width > 0, s.height > 0 else { return (0, 0, 0) }
            return (c.hotSpot.x / s.width, c.hotSpot.y / s.height, s.width / s.height)
        }
        let a = ratios(arrow), c = ratios(cursor)
        return abs(a.0 - c.0) < 0.02 && abs(a.1 - c.1) < 0.02 && abs(a.2 - c.2) < 0.02
    }

    static func readPointerScale() -> Double {
        let domain = "com.apple.universalaccess" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("mouseDriverCursorSize" as CFString, domain) as? Double ?? 1
        return min(max(value, 1), 4)
    }
}

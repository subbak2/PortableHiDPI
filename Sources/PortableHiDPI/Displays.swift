import AppKit
import CoreGraphics

/// Vendor ID stamped on the virtual displays we create, so we can tell them apart from real ones.
let virtualVendorID: UInt32 = 0x5048 // "PH"

struct Resolution: Hashable, CustomStringConvertible {
    let width: Int
    let height: Int
    var description: String { "\(width)×\(height)" }
    var storageValue: String { "\(width)x\(height)" }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        self.init(width: parts[0], height: parts[1])
    }
}

/// A real external display as seen by CoreGraphics.
struct PhysicalDisplay {
    let id: CGDirectDisplayID
    let name: String
    let native: Resolution
    let maxRefresh: Double
    let sizeInMillimeters: CGSize
    /// Chosen in the menu; overrides the EDID size, which is often wrong on portable monitors.
    var panelInches: Double?

    /// Stable across reconnects (same monitor, same port or not).
    var key: String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    var diagonalInches: Double? {
        if let panelInches { return panelInches }
        let w = Double(sizeInMillimeters.width), h = Double(sizeInMillimeters.height)
        guard w > 50, h > 50 else { return nil } // EDID missing
        return (w * w + h * h).squareRoot() / 25.4
    }

    /// Physical size for the virtual display, from the chosen diagonal and the panel's aspect ratio.
    var effectiveSizeInMillimeters: CGSize? {
        guard let diag = diagonalInches else { return nil }
        let w = Double(native.width), h = Double(native.height)
        let scale = diag * 25.4 / (w * w + h * h).squareRoot()
        return CGSize(width: w * scale, height: h * scale)
    }

    var supportedRefreshRates: [Double] {
        maxRefresh >= 119 ? [60, 120] : [60]
    }

    /// "Looks like" resolutions worth offering in HiDPI. macOS already offers native/2 itself,
    /// so these sit between native/2 and ~85% of native (beyond that text gets too small),
    /// rendered at 2x and scaled down to the panel.
    var candidates: [Resolution] {
        let aspect = Double(native.width) / Double(native.height)
        let widths = [1152, 1280, 1344, 1440, 1504, 1600, 1680, 1728, 1800, 1920, 2048, 2240, 2304, 2560, 2880, 3008, 3200]
        var result: [Resolution] = []
        for w in widths where w * 2 > native.width && Double(w) <= Double(native.width) * 0.85 && w * 2 <= 8192 {
            let exactH = Double(w) / aspect
            let h = Int(exactH.rounded())
            guard abs(exactH - Double(h)) < 1.5, h * 2 <= 8192 else { continue }
            result.append(Resolution(width: w, height: h))
        }
        return result
    }

    /// The candidate whose UI density is closest to a MacBook's built-in default (~125 points/inch).
    /// nil when macOS's own native/2 HiDPI mode is already the closest (e.g. 4K panels).
    var recommended: Resolution? {
        guard let diag = diagonalInches else { return nil }
        func distance(_ r: Resolution) -> Double {
            abs((Double(r.width * r.width + r.height * r.height)).squareRoot() / diag - 125)
        }
        guard let best = candidates.min(by: { distance($0) < distance($1) }) else { return nil }
        let builtIn = Resolution(width: native.width / 2, height: native.height / 2)
        return distance(best) < distance(builtIn) ? best : nil
    }
}

enum Displays {
    /// Common portable monitor sizes offered in the "Monitor Size" menu.
    static let panelSizes: [Double] = [13.3, 14, 15.6, 16, 17.3, 18.5]

    static let modeOptions = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary

    static func allModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(id, modeOptions) as? [CGDisplayMode]) ?? []
    }

    static func onlineIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func isOurs(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == virtualVendorID
    }

    /// External, non-virtual displays. Names are cached because a display that mirrors
    /// another one has no NSScreen of its own.
    static func externals(nameCache: inout [String: String]) -> [PhysicalDisplay] {
        var screenNames: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                screenNames[n.uint32Value] = screen.localizedName
            }
        }
        return onlineIDs().compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0, !isOurs(id), let native = nativeResolution(id) else { return nil }
            let key = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
            if let n = screenNames[id] { nameCache[key] = n }
            let name = nameCache[key] ?? "Display \(id)"
            let maxRefresh = allModes(id)
                .filter { $0.pixelWidth == native.width && $0.pixelHeight == native.height }
                .map(\.refreshRate).max() ?? 60
            let inches = UserDefaults.standard.double(forKey: "inches.\(key)")
            return PhysicalDisplay(id: id, name: name, native: native, maxRefresh: maxRefresh,
                                   sizeInMillimeters: CGDisplayScreenSize(id),
                                   panelInches: inches > 0 ? inches : nil)
        }
    }

    /// Panel resolution = the largest pixel size offered. The driver's "native" flag isn't used:
    /// many portable monitors ship a generic EDID that flags 1920×1080 on a 2560×1600 panel.
    static func nativeResolution(_ id: CGDirectDisplayID) -> Resolution? {
        guard let m = allModes(id).max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }) else { return nil }
        return Resolution(width: m.pixelWidth, height: m.pixelHeight)
    }

    /// A mode at the panel's full pixel size, refresh rate closest to `refresh`.
    static func nativeMode(_ id: CGDirectDisplayID, native: Resolution, refresh: Double) -> CGDisplayMode? {
        allModes(id)
            .filter { $0.pixelWidth == native.width && $0.pixelHeight == native.height }
            .min { abs($0.refreshRate - refresh) < abs($1.refreshRate - refresh) }
    }
}

import CGVirtualDisplayBridge
import CoreGraphics
import Foundation

enum HiDPIError: LocalizedError {
    case createFailed, applyFailed, modeNotFound, configureFailed(CGError)

    var errorDescription: String? {
        switch self {
        case .createFailed: return L("Could not create the virtual display.", "가상 디스플레이를 만들지 못했습니다.")
        case .applyFailed: return L("The virtual display rejected the resolution.", "가상 디스플레이가 해상도를 받아들이지 않았습니다.")
        case .modeNotFound: return L("macOS did not offer the HiDPI mode in time.", "macOS가 HiDPI 모드를 제때 띄우지 않았습니다.")
        case .configureFailed(let e): return L("Display configuration failed (\(e.rawValue)).", "디스플레이 설정에 실패했습니다 (\(e.rawValue)).")
        }
    }
}

/// One physical display mirrored from a HiDPI virtual display.
///
/// How it works: macOS only offers HiDPI modes up to the panel's own pixel size, so a
/// 2560×1600 panel can't "look like" 1680×1050 sharply (that needs a 3360×2100 backing store).
/// We create a virtual display that does offer 1680×1050 HiDPI, then make the real panel
/// mirror it at its native resolution. The GPU renders at 3360×2100 and scales to 2560×1600.
final class HiDPISession {
    let display: PhysicalDisplay
    let resolution: Resolution
    let refresh: Double
    private(set) var virtualDisplay: CGVirtualDisplay?
    private var originalMode: CGDisplayMode?

    var virtualID: CGDirectDisplayID? { virtualDisplay?.displayID }

    init(display: PhysicalDisplay, resolution: Resolution, refresh: Double) {
        self.display = display
        self.resolution = resolution
        self.refresh = refresh
    }

    func start(completion: @escaping (Error?) -> Void) {
        originalMode = CGDisplayCopyDisplayMode(display.id)

        let w = resolution.width, h = resolution.height
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "PortableHiDPI \(display.name)"
        descriptor.maxPixelsWide = UInt32(w * 2)
        descriptor.maxPixelsHigh = UInt32(h * 2)
        descriptor.sizeInMillimeters = virtualSizeInMillimeters()
        descriptor.vendorID = virtualVendorID
        descriptor.productID = CGDisplayModelNumber(display.id) & 0xFFFF
        descriptor.serialNum = CGDisplaySerialNumber(display.id) &+ UInt32(truncatingIfNeeded: display.id)

        guard let vd = CGVirtualDisplay(descriptor: descriptor) else {
            return completion(HiDPIError.createFailed)
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // Depending on the macOS version the mode size is read as points or pixels;
        // listing both makes the w×h HiDPI mode appear either way.
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(w * 2), height: UInt(h * 2), refreshRate: refresh),
            CGVirtualDisplayMode(width: UInt(w), height: UInt(h), refreshRate: refresh),
        ]
        guard vd.apply(settings) else {
            return completion(HiDPIError.applyFailed)
        }
        virtualDisplay = vd

        // The virtual display comes online asynchronously.
        waitForMode(attempt: 0) { [weak self] mode in
            guard let self else { return }
            guard let mode else {
                self.virtualDisplay = nil
                return completion(HiDPIError.modeNotFound)
            }
            do {
                try self.mirror(using: mode)
                completion(nil)
            } catch {
                // Earlier steps may already have changed the panel's mode: roll back.
                self.stop()
                completion(error)
            }
        }
    }

    /// Restores the panel's previous mode. Releasing the virtual display also ends the mirror.
    func stop() {
        defer { virtualDisplay = nil }
        guard let vid = virtualID, CGDisplayIsOnline(display.id) != 0 else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayMirrorOfDisplay(config, display.id, kCGNullDirectDisplay)
        let origin = CGDisplayBounds(vid).origin
        CGConfigureDisplayOrigin(config, display.id, Int32(origin.x), Int32(origin.y))
        if let originalMode {
            CGConfigureDisplayWithDisplayMode(config, display.id, originalMode, nil)
        }
        let err = CGCompleteDisplayConfiguration(config, .forSession)
        if err != .success {
            // Releasing the virtual display below still ends the mirror; macOS then picks a mode itself.
            NSLog("PortableHiDPI: restore failed: \(err.rawValue)")
            CGCancelDisplayConfiguration(config)
        }
    }

    // MARK: - Private

    private func virtualSizeInMillimeters() -> CGSize {
        if let mm = display.effectiveSizeInMillimeters { return mm }
        // No EDID size: assume ~110 points per inch.
        return CGSize(width: Double(resolution.width) / 110 * 25.4,
                      height: Double(resolution.height) / 110 * 25.4)
    }

    private func findMode(on vid: CGDirectDisplayID) -> CGDisplayMode? {
        Displays.allModes(vid)
            .filter { $0.width == resolution.width && $0.height == resolution.height
                && $0.pixelWidth == resolution.width * 2 && $0.pixelHeight == resolution.height * 2 }
            .min { abs($0.refreshRate - refresh) < abs($1.refreshRate - refresh) }
    }

    private func waitForMode(attempt: Int, _ done: @escaping (CGDisplayMode?) -> Void) {
        if let vid = virtualID, let mode = findMode(on: vid) { return done(mode) }
        guard attempt < 30, virtualDisplay != nil else { return done(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForMode(attempt: attempt + 1, done) ?? done(nil)
        }
    }

    private func mirror(using mode: CGDisplayMode) throws {
        guard let vid = virtualID else { throw HiDPIError.createFailed }
        let origin = CGDisplayBounds(display.id).origin

        // Done as separate transactions: macOS rejects (kCGErrorInvalidOperation) a single
        // transaction that both sets modes and builds the mirror set.
        try configure("virtual mode") { config in
            CGConfigureDisplayWithDisplayMode(config, vid, mode, nil)
            // Put the virtual display where the panel was, so the arrangement doesn't jump.
            CGConfigureDisplayOrigin(config, vid, Int32(origin.x), Int32(origin.y))
        }
        try configure("mirror") { config in
            CGConfigureDisplayMirrorOfDisplay(config, display.id, vid)
        }
        enforcePanelMode()
    }

    /// Joining a mirror set makes macOS drive the panel with the virtual display's mode
    /// (3360×2100 and so on), which the monitor's scaler shrinks with black borders.
    /// Set the panel back to its own pixel size; called again after every display change.
    func enforcePanelMode() {
        guard virtualID != nil, CGDisplayIsOnline(display.id) != 0,
              let current = CGDisplayCopyDisplayMode(display.id),
              current.pixelWidth != display.native.width || current.pixelHeight != display.native.height,
              let native = Displays.nativeMode(display.id, native: display.native, refresh: refresh)
        else { return }
        try? configure("panel native mode") { config in
            CGConfigureDisplayWithDisplayMode(config, display.id, native, nil)
        }
    }

    private func configure(_ step: String, _ body: (CGDisplayConfigRef?) -> Void) throws {
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success else { throw HiDPIError.configureFailed(err) }
        body(config)
        err = CGCompleteDisplayConfiguration(config, .forSession)
        if err != .success {
            NSLog("PortableHiDPI: \(step) failed: \(err.rawValue)")
            CGCancelDisplayConfiguration(config)
            throw HiDPIError.configureFailed(err)
        }
        NSLog("PortableHiDPI: \(step) ok")
    }
}

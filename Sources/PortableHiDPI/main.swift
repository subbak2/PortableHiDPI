import AppKit

// Command line (optional):
//   PortableHiDPI --list                 print external displays and HiDPI options, then exit
//   PortableHiDPI --apply 1680x1050      remember this resolution for the first external display and run
//   PortableHiDPI --apply off            forget the setting for the first external display and run
//   PortableHiDPI --inches 16 ...        set the first external display's size (EDIDs are often wrong)
let args = CommandLine.arguments
if args.contains("--list") || args.contains("--apply") || args.contains("--inches") {
    var cache: [String: PhysicalDisplay] = [:]
    var externals = Displays.externals(cache: &cache)
    if let i = args.firstIndex(of: "--inches"), i + 1 < args.count, let inches = Double(args[i + 1]), let d = externals.first {
        UserDefaults.standard.set(inches, forKey: "inches.\(d.key)")
        externals = Displays.externals(cache: &cache)
    }
    if args.contains("--list") {
        if externals.isEmpty { print("No external display (monitors HiDPI is currently on for are not listed)") }
        for d in externals {
            let size = d.diagonalInches.map { String(format: " %.1f\"", $0) } ?? ""
            print("\(d.name) [\(d.key)] native \(d.native)\(size) max \(Int(d.maxRefresh))Hz")
            for r in d.candidates {
                print("  \(r.storageValue)\(r == d.recommended ? "  (recommended)" : "")")
            }
        }
        exit(0)
    }
    if let i = args.firstIndex(of: "--apply"), i + 1 < args.count, let d = externals.first {
        let value = args[i + 1]
        if value == "off" {
            UserDefaults.standard.removeObject(forKey: "hidpi.\(d.key)")
        } else if let r = Resolution(storageValue: value), d.candidates.contains(r) {
            UserDefaults.standard.set(r.storageValue, forKey: "hidpi.\(d.key)")
        } else {
            print("Unsupported resolution \(value). Run --list for options.")
            exit(1)
        }
    }
}

// Quit cleanly on Ctrl-C / kill so the monitor gets its previous mode back.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { NSApp.terminate(nil) }
    source.resume()
    signalSources.append(source)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()

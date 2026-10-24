// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortableHiDPI",
    platforms: [.macOS(.v13)],
    targets: [
        // Declarations for the private CGVirtualDisplay classes (implemented in CoreGraphics).
        .target(
            name: "CGVirtualDisplayBridge",
            path: "Sources/CGVirtualDisplayBridge"
        ),
        .executableTarget(
            name: "PortableHiDPI",
            dependencies: ["CGVirtualDisplayBridge"],
            path: "Sources/PortableHiDPI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)

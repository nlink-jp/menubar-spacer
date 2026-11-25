// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenubarSpacer",
    // macOS 26 baseline: the spacing behaviour of NSStatusItemSpacing /
    // NSStatusItemSelectionPadding was measured on 27.0 (26A428) and reproduced
    // value for value on 26.7.1 (25G241) — evidence/2026-11-25-macos26/. The
    // string form is used deliberately — a `.vNN` platform enum case may not
    // exist in older toolchains, whereas "26.0" is accepted by any SwiftPM whose
    // SDK provides it.
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MenubarSpacer",
            path: "Sources/MenubarSpacer"
        ),
        // Development-only measurement target for the Phase 1 hardware checks.
        // It is not copied into the .app bundle by `make build-app`.
        .executableTarget(
            name: "SpacingProbe",
            path: "Sources/SpacingProbe"
        ),
        .testTarget(
            name: "MenubarSpacerTests",
            dependencies: ["MenubarSpacer"],
            path: "Tests/MenubarSpacerTests"
        ),
    ]
)

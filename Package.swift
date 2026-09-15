// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenubarSpacer",
    // macOS 27 baseline: the spacing behaviour of NSStatusItemSpacing /
    // NSStatusItemSelectionPadding was only measured on 27.0 (26A428). The string
    // form is used deliberately — the `.v27` platform enum case may not exist in
    // older toolchains, whereas "27.0" is accepted by any SwiftPM whose SDK
    // provides it.
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(
            name: "MenubarSpacer",
            path: "Sources/MenubarSpacer"
        ),
        .testTarget(
            name: "MenubarSpacerTests",
            dependencies: ["MenubarSpacer"],
            path: "Tests/MenubarSpacerTests"
        ),
    ]
)

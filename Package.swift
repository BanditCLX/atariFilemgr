// swift-tools-version: 5.9
// AtariFileMgr — Atari ST Disk Image Editor for macOS
import PackageDescription

let package = Package(
    name: "AtariFileMgr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AtariFileMgr", targets: ["AtariFileMgr"])
    ],
    targets: [
        .executableTarget(
            name: "AtariFileMgr",
            path: "Sources/AtariFileMgr",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

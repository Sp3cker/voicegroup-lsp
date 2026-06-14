// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "voicegroup-lsp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "voicegroup-lsp", targets: ["voicegroup-lsp"]),
        .library(name: "VoicegroupBridge", type: .dynamic, targets: ["VoicegroupBridge"]),
        .library(name: "VoicegroupCore", targets: ["VoicegroupCore"]),
        .library(name: "VoicegroupLSP", targets: ["VoicegroupLSP"])
    ],
    targets: [
        .target(name: "VoicegroupBridge", dependencies: ["VoicegroupCore"]),
        .target(name: "VoicegroupCore"),
        .target(name: "VoicegroupLSP", dependencies: ["VoicegroupCore"]),
        .executableTarget(name: "voicegroup-lsp", dependencies: ["VoicegroupLSP"]),
        .testTarget(name: "VoicegroupBridgeTests", dependencies: ["VoicegroupBridge"]),
        .testTarget(name: "VoicegroupCoreTests", dependencies: ["VoicegroupCore"]),
        .testTarget(name: "VoicegroupLSPTests", dependencies: ["VoicegroupLSP", "VoicegroupCore"])
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "voicegroup-lsp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "voicegroup-lsp", targets: ["voicegroup-lsp"]),
        .library(name: "VoicegroupCore", targets: ["VoicegroupCore"]),
        .library(name: "VoicegroupLSP", targets: ["VoicegroupLSP"])
    ],
    targets: [
        .target(name: "VoicegroupCore"),
        .target(name: "VoicegroupLSP", dependencies: ["VoicegroupCore"]),
        .executableTarget(name: "voicegroup-lsp", dependencies: ["VoicegroupLSP"]),
        .testTarget(name: "VoicegroupCoreTests", dependencies: ["VoicegroupCore"]),
        .testTarget(name: "VoicegroupLSPTests", dependencies: ["VoicegroupLSP", "VoicegroupCore"])
    ]
)

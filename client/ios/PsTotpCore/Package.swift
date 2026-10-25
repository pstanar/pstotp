// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PsTotpCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PsTotpCore", targets: ["PsTotpCore"]),
    ],
    targets: [
        // Vendored Argon2 reference implementation (CC0 / Apache-2.0). See Sources/CArgon2/README.md.
        .target(
            name: "CArgon2",
            exclude: ["README.md", "LICENSE"],
            sources: ["argon2.c", "core.c", "encoding.c", "ref.c", "thread.c", "blake2/blake2b.c"],
            publicHeadersPath: "include"
        ),
        .target(name: "PsTotpCore", dependencies: ["CArgon2"]),
        .testTarget(
            name: "PsTotpCoreTests",
            dependencies: ["PsTotpCore"],
            resources: [.copy("Vectors")]
        ),
    ]
)

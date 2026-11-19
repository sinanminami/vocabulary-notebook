// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VocabularyKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VocabularyCore", targets: ["VocabularyCore"]),
        .library(name: "VocabularyPersistence", targets: ["VocabularyPersistence"]),
        .library(name: "VocabularyAI", targets: ["VocabularyAI"])
    ],
    dependencies: [
        // Pinned, shallow-vendored source avoids downloading the repository's
        // full history on every clean development machine.
        .package(path: "../Vendor/GRDB.swift"),
        // Official open-spaced-repetition Swift implementation, vendored at
        // commit 4fbaf20184d62f82a9f44f343337c61a2c5483e9.
        .package(path: "../Vendor/swift-fsrs")
    ],
    targets: [
        .target(name: "VocabularyCore"),
        .target(
            name: "VocabularyPersistence",
            dependencies: [
                "VocabularyCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "FSRS", package: "swift-fsrs")
            ]
        ),
        .target(
            name: "VocabularyAI",
            dependencies: ["VocabularyCore"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "VocabularyCoreTests",
            dependencies: ["VocabularyCore"]
        ),
        .testTarget(
            name: "VocabularyPersistenceTests",
            dependencies: [
                "VocabularyCore",
                "VocabularyPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "VocabularyAITests",
            dependencies: ["VocabularyCore", "VocabularyAI"]
        )
    ]
)

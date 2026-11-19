import Foundation
import GRDB

public final class AppDatabase: @unchecked Sendable {
    let queue: DatabaseQueue

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        queue = try DatabaseQueue(path: path, configuration: configuration)
        try DatabaseMigrations.migrator.migrate(queue)
    }

    private init(inMemory: Void) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        queue = try DatabaseQueue(configuration: configuration)
        try DatabaseMigrations.migrator.migrate(queue)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(inMemory: ())
    }

    public static func live(bundleIdentifier: String) throws -> AppDatabase {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appending(
            path: bundleIdentifier,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "Vocabulary.sqlite")
        return try AppDatabase(path: databaseURL.path)
    }
}

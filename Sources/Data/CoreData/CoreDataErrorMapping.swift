//  Created by Junhao Huang on 2026/10/18.

import CoreData

extension RepositoryError {
    enum Access: Sendable {
        case read
        case write
    }

    /// Maps a Core Data, mapping or model error to the error use cases handle.
    init(coreDataError error: Error, during access: Access) {
        if let repositoryError = error as? RepositoryError {
            self = repositoryError
            return
        }
        if error is CoreDataMappingError {
            self = .readFailed
            return
        }
        if error is ManagedObjectCreationError || error is PersistenceControllerError {
            self = .storeUnavailable
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, Self.storeErrorCodes.contains(nsError.code) {
            self = .storeUnavailable
            return
        }
        self = access == .read ? .readFailed : .writeFailed
    }

    /// Errors that mean the store itself cannot be used, not that one request was invalid.
    private static let storeErrorCodes: Set<Int> = [
        NSPersistentStoreInvalidTypeError,
        NSPersistentStoreTypeMismatchError,
        NSPersistentStoreIncompatibleSchemaError,
        NSCoreDataError,
        NSPersistentStoreOperationError,
        NSPersistentStoreOpenError,
        NSPersistentStoreTimeoutError,
        NSPersistentStoreIncompatibleVersionHashError,
        NSMigrationError,
        NSSQLiteError
    ]
}

//  Created by Junhao Huang on 2026/10/17.

/// Storage failures that repositories report to use cases.
enum RepositoryError: Error, Equatable, Sendable {
    case notFound
    case readFailed
    case writeFailed
    case storeUnavailable
}

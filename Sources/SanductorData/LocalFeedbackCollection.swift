import Foundation
import SanductorDomain

// MARK: - LocalFeedbackCollection

/// Captured local evidence is valid only for the exact code and selected reviewer.
public struct LocalFeedbackCollection: Codable, Equatable, Sendable {
    public let id: String
    public let revision: String
    public let configuration: String
    public var isPending = true
    public var review: LocalReview?
    public var failure: String?
}

// MARK: - FeedbackCollector

/// Feedback work runs beside the existing refresh, never inside its critical path.
actor FeedbackCollector {
    // MARK: Internal

    func isRunning(_ key: String) -> Bool {
        tasks[key] != nil
    }

    func start(
        _ key: String,
        minimumInterval: TimeInterval = 0,
        now: Date = Date(),
        operation: @escaping @Sendable () async -> Void,
    ) {
        guard tasks[key] == nil,
              lastStarted[key].map({ now < $0 || now.timeIntervalSince($0) >= minimumInterval }) ?? true
        else {
            return
        }

        if minimumInterval > 0 {
            lastStarted[key] = now
        }
        tasks[key] = Task {
            await operation()
            tasks[key] = nil
        }
    }

    func wait(_ key: String) async {
        await tasks[key]?.value
    }

    // MARK: Private

    private var tasks: [String: Task<Void, Never>] = [:]
    private var lastStarted: [String: Date] = [:]
}

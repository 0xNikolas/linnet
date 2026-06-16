import Foundation
import GRDB
import Observation
import os

private let logger = Logger(subsystem: "com.linnet.app", category: "database")

/// Wraps a GRDB ValueObservation for use in SwiftUI.
/// Publishes the latest fetched value and automatically updates when the database changes.
@Observable
@MainActor
public final class DatabaseObserver<Value: Sendable> {
    public private(set) var value: Value
    /// The most recent observation error, or nil if the latest fetch succeeded.
    /// Cleared whenever a fresh value is delivered. Observe this to surface a
    /// failure in the UI instead of silently showing stale data.
    public private(set) var lastError: Error?
    private nonisolated(unsafe) var cancellable: AnyDatabaseCancellable?

    public init(
        initial: Value,
        in pool: DatabasePool,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        self.value = initial
        start(in: pool, observation: observation)
    }

    /// Replace the current observation with a new one (e.g. when sort/filter changes).
    public func reobserve(
        in pool: DatabasePool,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        start(in: pool, observation: observation)
    }

    private func start(
        in pool: DatabasePool,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        cancellable?.cancel()
        cancellable = observation.start(
            in: pool,
            scheduling: .mainActor,
            onError: { [weak self] error in
                // `.mainActor` scheduling guarantees delivery on the main actor.
                MainActor.assumeIsolated {
                    // Don't swallow the failure: a thrown fetch would otherwise
                    // leave `value` stale and look like "nothing happened" to the
                    // user. Log it, expose it via `lastError`, and trip an assertion
                    // in debug so the bug surfaces during development.
                    logger.error("DatabaseObserver observation failed: \(String(describing: error), privacy: .public)")
                    self?.lastError = error
                    assertionFailure("DatabaseObserver observation failed: \(error)")
                }
            },
            onChange: { [weak self] newValue in
                // `.mainActor` guarantees delivery on the main actor, so assign
                // directly — no Task hop, which preserves change ordering.
                MainActor.assumeIsolated {
                    self?.value = newValue
                    self?.lastError = nil
                }
            }
        )
    }

    deinit {
        cancellable?.cancel()
    }
}

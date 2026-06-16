import Foundation
import GRDB
import Observation

/// Wraps a GRDB ValueObservation for use in SwiftUI.
/// Publishes the latest fetched value and automatically updates when the database changes.
@Observable
@MainActor
public final class DatabaseObserver<Value: Sendable> {
    public private(set) var value: Value
    private nonisolated(unsafe) var cancellable: AnyDatabaseCancellable?

    public init(
        initial: Value,
        in pool: DatabasePool,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        self.value = initial
        self.cancellable = observation.start(
            in: pool,
            scheduling: .mainActor,
            onError: { error in
                print("DatabaseObserver error: \(error)")
            },
            onChange: { [weak self] newValue in
                // `.mainActor` guarantees delivery on the main actor, so assign
                // directly — no Task hop, which preserves change ordering.
                MainActor.assumeIsolated {
                    self?.value = newValue
                }
            }
        )
    }

    /// Replace the current observation with a new one (e.g. when sort/filter changes).
    public func reobserve(
        in pool: DatabasePool,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        cancellable?.cancel()
        self.cancellable = observation.start(
            in: pool,
            scheduling: .mainActor,
            onError: { error in
                print("DatabaseObserver error: \(error)")
            },
            onChange: { [weak self] newValue in
                // `.mainActor` guarantees delivery on the main actor, so assign
                // directly — no Task hop, which preserves change ordering.
                MainActor.assumeIsolated {
                    self?.value = newValue
                }
            }
        )
    }

    deinit {
        cancellable?.cancel()
    }
}

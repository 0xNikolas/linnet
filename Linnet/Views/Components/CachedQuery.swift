import SwiftUI
import GRDB
import LinnetLibrary

/// Main-actor-isolated cache that survives the SwiftUI view lifecycle, replacing the
/// per-view `nonisolated(unsafe)` global caches. Because it is actor-isolated the
/// storage is free of data races without any `unsafe` annotation.
///
/// Keys are namespaced strings (e.g. "albumGrid", "albumDetail-42"). Values are
/// type-erased; callers always read back with the same concrete type they stored.
@MainActor
enum ViewDataCache {
    private static var storage: [String: Any] = [:]

    static func value<Value>(forKey key: String) -> Value? { storage[key] as? Value }
    static func store<Value>(_ value: Value, forKey key: String) { storage[key] = value }
}

/// A database-backed value for SwiftUI views that bundles what every list/detail
/// screen previously hand-rolled:
///   1. an instant seed from `ViewDataCache` (no empty flash when navigating back),
///   2. a live `DatabaseObserver` that republishes changes, and
///   3. `persist()` to write the current value back into the cache.
///
/// Hold one in `@State`, read `value` in the body, call `activate` from `.task`,
/// `reobserve` from the `onChange(of:)` handlers that change the query (sort/search),
/// and `persist()` from the handler that decides when caching is appropriate (the
/// view keeps that decision because it depends on live state like `searchText`).
@MainActor
@Observable
final class CachedQuery<Value: Sendable> {
    /// Tracked: stored (not computed from the `@ObservationIgnored` observer) so SwiftUI
    /// re-renders when the observation delivers fresh data. A computed passthrough would
    /// never establish a dependency, leaving the view stuck on the seed value.
    private(set) var value: Value

    @ObservationIgnored private let cacheKey: String
    @ObservationIgnored private var observer: DatabaseObserver<Value>?

    /// - Parameters:
    ///   - cacheKey: Namespaced cache key, unique per screen (and per entity for detail views).
    ///   - default: Value shown before the first fetch when the cache is cold.
    init(cacheKey: String, default defaultValue: Value) {
        self.cacheKey = cacheKey
        self.value = ViewDataCache.value(forKey: cacheKey) ?? defaultValue
    }

    /// Start observing once. On a cold cache, `seed` supplies the first value synchronously
    /// so the view renders populated immediately.
    func activate(
        in pool: DatabasePool,
        seed: (Database) throws -> Value,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        guard observer == nil else { return }
        if ViewDataCache.value(forKey: cacheKey) as Value? == nil, let value = try? pool.read(seed) {
            self.value = value
        }
        let observer = DatabaseObserver(initial: value, in: pool, observation: observation)
        observer.onChange = { [weak self] newValue in self?.value = newValue }
        self.observer = observer
    }

    /// Replace the observation when the query changes (e.g. sort or search text).
    func reobserve(
        in pool: DatabasePool,
        observation: ValueObservation<ValueReducers.Fetch<Value>>
    ) {
        observer?.reobserve(in: pool, observation: observation)
    }

    /// Write the current value into the cache under this query's key. Callers gate this
    /// on live state (e.g. only when the search field is empty) so filtered results
    /// don't get cached and shown as the seed on the next visit.
    func persist() {
        ViewDataCache.store(value, forKey: cacheKey)
    }
}

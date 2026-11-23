import Foundation

/// Minimal key-value storage abstraction so settings persistence is testable.
public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

/// `UserDefaults`-backed storage used by the app.
public final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func setData(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// In-memory storage for tests and previews.
public final class InMemoryStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { storage[key] }
    public func setData(_ data: Data?, forKey key: String) { storage[key] = data }
}

/// Loads and saves `NoelifySettings`.
public final class SettingsStore {
    public static let key = "noelify.settings.v1"

    private let store: KeyValueStore

    public init(store: KeyValueStore) {
        self.store = store
    }

    /// Returns stored settings, or defaults when nothing (or something unreadable) is stored.
    public func load() -> NoelifySettings {
        guard let data = store.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(NoelifySettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: NoelifySettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.setData(data, forKey: Self.key)
    }
}

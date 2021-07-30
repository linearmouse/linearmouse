// Modified from https://github.com/xavierLowmiller/AppStorage/
// MIT License
// Copyright (c) 2020 Xavier Lowmiller

import SwiftUI

/// A property wrapper type that reflects a value from `UserDefaults` and
/// invalidates a view on a change in value in that user default.
@frozen @propertyWrapper public struct AppStorageCompat<Value> : DynamicProperty {

    @ObservedObject private var _value: Storage<Value>
    private let saveValue: (Value) -> Void

    private init(value: Value, store: UserDefaults, key: String, transform: @escaping (Any?) -> Value?, saveValue: @escaping (Value) -> Void) {
        _value = Storage(value: value, store: store, key: key, transform: transform)
        self.saveValue = saveValue
    }

    public var wrappedValue: Value {
        get {
            _value.value
        }
        nonmutating set {
            saveValue(newValue)
            _value.value = newValue
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

@usableFromInline
final class Storage<Value>: NSObject, ObservableObject {
    @Published var value: Value
    private let defaultValue: Value
    private let store: UserDefaults
    private let keyPath: String
    private let transform: (Any?) -> Value?

    init(value: Value, store: UserDefaults, key: String, transform: @escaping (Any?) -> Value?) {
        self.value = value
        self.defaultValue = value
        self.store = store
        self.keyPath = key
        self.transform = transform
        super.init()

        store.addObserver(self, forKeyPath: key, options: [.new], context: nil)
    }

    deinit {
        store.removeObserver(self, forKeyPath: keyPath)
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {

        value = change?[.newKey].flatMap(transform) ?? defaultValue
    }
}

extension AppStorageCompat where Value == Bool {

    /// Creates a property that can read and write to a boolean user default.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if a boolean value is not specified
    ///     for the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let initialValue = store.value(forKey: key) as? Value ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            $0 as? Value
        }, saveValue: { newValue in
            store.setValue(newValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value == Int {
    /// Creates a property that can read and write to an integer user default.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if an integer value is not specified
    ///     for the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let initialValue = store.value(forKey: key) as? Value ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            $0 as? Value
        }, saveValue: { newValue in
            store.setValue(newValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value == Double {

    /// Creates a property that can read and write to a double user default.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if a double value is not specified
    ///     for the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let initialValue = store.value(forKey: key) as? Value ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            $0 as? Value
        }, saveValue: { newValue in
            store.setValue(newValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value == String {

    /// Creates a property that can read and write to a string user default.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if a string value is not specified
    ///     for the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let initialValue = store.value(forKey: key) as? Value ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            $0 as? Value
        }, saveValue: { newValue in
            store.setValue(newValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value == URL {

    /// Creates a property that can read and write to a url user default.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if a url value is not specified for
    ///     the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let initialValue = store.url(forKey: key) ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            ($0 as? String).flatMap(URL.init)
        }, saveValue: { newValue in
            store.set(newValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value == Data {

    /// Creates a property that can read and write to a user default as data.
    ///
    /// Avoid storing large data blobs in user defaults, such as image data,
    /// as it can negatively affect performance of your app. On tvOS, a
    /// `NSUserDefaultsSizeLimitExceededNotification` notification is posted
    /// if the total user default size reaches 512kB.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if a data value is not specified for
    ///    the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let initialValue = store.value(forKey: key) as? Value ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            $0 as? Value
        }, saveValue: { newValue in
            store.setValue(newValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value : RawRepresentable, Value.RawValue == Int {

    /// Creates a property that can read and write to an integer user default,
    /// transforming that to `RawRepresentable` data type.
    ///
    /// A common usage is with enumerations:
    ///
    ///    enum MyEnum: Int {
    ///        case a
    ///        case b
    ///        case c
    ///    }
    ///    struct MyView: View {
    ///        @AppStorage("MyEnumValue") private var value = MyEnum.a
    ///        var body: some View { ... }
    ///    }
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if an integer value
    ///     is not specified for the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let rawValue = store.value(forKey: key) as? Int
        let initialValue = rawValue.flatMap(Value.init) ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            ($0 as? Int).flatMap(Value.init)
        }, saveValue: { newValue in
            store.setValue(newValue.rawValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value : RawRepresentable, Value.RawValue == String {

    /// Creates a property that can read and write to a string user default,
    /// transforming that to `RawRepresentable` data type.
    ///
    /// A common usage is with enumerations:
    ///
    ///    enum MyEnum: String {
    ///        case a
    ///        case b
    ///        case c
    ///    }
    ///    struct MyView: View {
    ///        @AppStorage("MyEnumValue") private var value = MyEnum.a
    ///        var body: some View { ... }
    ///    }
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value if a string value
    ///     is not specified for the given key.
    ///   - key: The key to read and write the value to in the user defaults
    ///     store.
    ///   - store: The user defaults store to read and write to. A value
    ///     of `nil` will use the user default store from the environment.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        let rawValue = store.value(forKey: key) as? String
        let initialValue = rawValue.flatMap(Value.init) ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            ($0 as? String).flatMap(Value.init)
        }, saveValue: { newValue in
            store.setValue(newValue.rawValue, forKey: key)
        })
    }
}

extension AppStorageCompat where Value : Codable {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        let store = (store ?? .standard)
        var parsedValue: Value?
        if let rawValue = store.data(forKey: key) {
            do {
                parsedValue = try PropertyListDecoder().decode(Value.self, from: rawValue)
            } catch {}
        }
        let initialValue = parsedValue ?? wrappedValue
        self.init(value: initialValue, store: store, key: key, transform: {
            guard let value = $0 as? Data else { return initialValue }
            do {
                return try PropertyListDecoder().decode(Value.self, from: value)
            } catch {
                return initialValue
            }
        }, saveValue: { newValue in
            do {
                store.setValue(try PropertyListEncoder().encode(newValue), forKey: key)
            } catch {
            }
        })
    }
}

//
//  PublishedPersist.swift
//  MobileAffine
//
//  Created by 秋星桥 on 2024/6/28.
//

import Combine
import Foundation

@propertyWrapper
struct PublishedPersist<Value: Codable> {
    @Persist private var value: Value

    var projectedValue: AnyPublisher<Value, Never> { $value }

    @available(*, unavailable, message: "accessing wrappedValue will result undefined behavior")
    var wrappedValue: Value {
        get { value }
        set { value = newValue }
    }

    static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped _: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, PublishedPersist<Value>>
    ) -> Value {
        get { object[keyPath: storageKeyPath].value }
        set {
            (object.objectWillChange as? ObservableObjectPublisher)?.send()
            object[keyPath: storageKeyPath].value = newValue
        }
    }

    init(key: String, defaultValue: Value, engine: PersistProvider) {
        _value = .init(key: key, defaultValue: defaultValue, engine: engine)
    }

    func invalidateCaches() {
        _value.invalidateCaches()
    }

    func saveNow() {
        _value.saveNow()
    }
}

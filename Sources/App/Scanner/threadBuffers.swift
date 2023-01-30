import Foundation

actor CrossThreadDictionarySet<T: Hashable, V: Hashable> {
    var keys = Set<T>()
    var elements = [T: Set<V>]()

    init() {
        keys = []
        elements = [:]
    }

    func insert(_ key: T, _ value: V) {
        keys.insert(key)
        if elements[key] == nil {
            elements[key] = []
        }
        elements[key]!.insert(value)
    }

    func key(_ key: T) {
        if keys.insert(key).inserted {
            elements[key] = []
        }
    }

    func remove(_ key: T, _ value: V) {
        elements[key]!.remove(value)
        if elements[key]!.isEmpty {
            elements[key] = nil
            keys.remove(key)
        }
    }
}

actor CrossThreadSet<V: Hashable> {
    var elements = Set<V>()

    init() {
        elements = []
    }

    func insert(_ value: V) {
        elements.insert(value)
    }

    func insert(_ values: [V]) {
        for value in values {
            elements.insert(value)
        }
    }

    func remove(_ value: V) {
        elements.remove(value)
    }
}

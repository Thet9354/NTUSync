import Foundation

/// Array-backed binary min-heap. Decrease-key is handled by lazy deletion in
/// the caller (push duplicates, skip settled entries on pop).
nonisolated struct PriorityHeap<Element: Comparable> {
    private var storage: [Element] = []

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    mutating func push(_ element: Element) {
        storage.append(element)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard storage[child] < storage[parent] else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Element? {
        guard let top = storage.first else { return nil }
        storage.swapAt(0, storage.count - 1)
        storage.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var smallest = parent
            if left < storage.count && storage[left] < storage[smallest] { smallest = left }
            if right < storage.count && storage[right] < storage[smallest] { smallest = right }
            guard smallest != parent else { break }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
        return top
    }
}

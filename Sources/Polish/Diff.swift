import SwiftUI

enum Diff {
    enum Part: Equatable {
        case same(String), removed(String), added(String)
    }

    /// Word-level diff: words, runs of whitespace, and single punctuation marks are the units.
    static func parts(from old: String, to new: String) -> [Part] {
        let a = tokens(old), b = tokens(new)
        var removed = Set<Int>(), added = Set<Int>()
        for change in b.difference(from: a) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }

        var parts: [Part] = []
        func append(_ part: Part) {
            switch (parts.last, part) {
            case (.same(let x)?, .same(let y)): parts[parts.count - 1] = .same(x + y)
            case (.removed(let x)?, .removed(let y)): parts[parts.count - 1] = .removed(x + y)
            case (.added(let x)?, .added(let y)): parts[parts.count - 1] = .added(x + y)
            default: parts.append(part)
            }
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                append(.removed(a[i])); i += 1
            } else if j < b.count, added.contains(j) {
                append(.added(b[j])); j += 1
            } else {
                append(.same(b[j])); i += 1; j += 1
            }
        }
        return parts
    }

    /// Number of edits; a removal directly followed by its replacement counts as one.
    static func changeCount(_ parts: [Part]) -> Int {
        parts.indices.filter { i in
            switch parts[i] {
            case .same: false
            case .removed: true
            case .added: if i > 0, case .removed = parts[i - 1] { false } else { true }
            }
        }.count
    }

    static func attributed(_ parts: [Part]) -> AttributedString {
        parts.reduce(into: AttributedString()) { out, part in
            switch part {
            case .same(let s):
                out += AttributedString(s)
            case .removed(let s):
                var r = AttributedString(s)
                r.foregroundColor = .red
                r.backgroundColor = .red.opacity(0.3)
                r.strikethroughStyle = .single
                out += r
            case .added(let s):
                var r = AttributedString(s)
                r.foregroundColor = .green
                r.backgroundColor = .green.opacity(0.3)
                out += r
            }
        }
    }

    private static func tokens(_ s: String) -> [String] {
        s.matches(of: /\w+|\s+|[^\w\s]/).map { String($0.output) }
    }
}

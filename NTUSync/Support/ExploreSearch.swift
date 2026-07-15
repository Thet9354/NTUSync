import Foundation

/// One searchable thing on the Explore map. `key` is an opaque "<kind>:<id>"
/// string the UI maps back to a building, amenity, bench, or user place —
/// keeping this layer free of models and MapKit.
nonisolated struct SearchCandidate: Sendable, Hashable, Identifiable {
    let key: String
    let title: String
    let subtitle: String?
    let icon: String
    let latitude: Double
    let longitude: Double

    var id: String { key }
}

/// Pure, offline search over the campus dataset — graph buildings, curated
/// amenities, benches, and user pins. Deliberately NOT MKLocalSearch: results
/// can only ever be NTU campus content, and it works in a basement.
nonisolated enum ExploreSearch {

    /// Case- and diacritic-insensitive match; prefix hits rank above interior
    /// hits, ties break alphabetically. Empty/whitespace queries match nothing.
    static func matches(query: String, in candidates: [SearchCandidate],
                        limit: Int = 12) -> [SearchCandidate] {
        let needle = fold(query)
        guard !needle.isEmpty else { return [] }

        let scored: [(candidate: SearchCandidate, isPrefix: Bool)] = candidates.compactMap {
            let haystack = fold($0.title)
            guard haystack.contains(needle) else { return nil }
            return ($0, haystack.hasPrefix(needle))
        }
        return scored
            .sorted {
                if $0.isPrefix != $1.isPrefix { return $0.isPrefix }
                return $0.candidate.title.localizedCaseInsensitiveCompare($1.candidate.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.candidate)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

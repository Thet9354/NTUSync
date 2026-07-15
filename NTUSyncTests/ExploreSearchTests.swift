import Testing
import Foundation
@testable import NTUSync

struct ExploreSearchTests {

    static func candidate(_ title: String, key: String? = nil) -> SearchCandidate {
        SearchCandidate(key: key ?? "node:\(title)", title: title, subtitle: nil,
                        icon: "building.2", latitude: 1.34, longitude: 103.68)
    }

    static let campus = [
        candidate("Lee Wee Nam Library"),
        candidate("North Spine Plaza"),
        candidate("North Hill Halls"),
        candidate("Canteen 2"),
        candidate("PEN & INC Restaurant & Bar"),
        candidate("Hall 2 Gym"),
    ]

    @Test func emptyOrWhitespaceQueryMatchesNothing() {
        #expect(ExploreSearch.matches(query: "", in: Self.campus).isEmpty)
        #expect(ExploreSearch.matches(query: "   ", in: Self.campus).isEmpty)
    }

    @Test func matchingIsCaseInsensitive() {
        let results = ExploreSearch.matches(query: "lee wee nam", in: Self.campus)
        #expect(results.map(\.title) == ["Lee Wee Nam Library"])
    }

    @Test func prefixMatchesRankAboveInteriorMatches() {
        // "north" prefixes two entries; "canteen" only contains it interior — none here,
        // so use "hall": prefix of "Hall 2 Gym", interior of "North Hill Halls".
        let results = ExploreSearch.matches(query: "hall", in: Self.campus)
        #expect(results.first?.title == "Hall 2 Gym")
        #expect(results.map(\.title).contains("North Hill Halls"))
    }

    @Test func tiesBreakAlphabetically() {
        let results = ExploreSearch.matches(query: "north", in: Self.campus)
        #expect(results.map(\.title) == ["North Hill Halls", "North Spine Plaza"])
    }

    @Test func noMatchYieldsEmpty() {
        #expect(ExploreSearch.matches(query: "starbucks", in: Self.campus).isEmpty)
    }

    @Test func limitCapsResults() {
        let many = (1...20).map { Self.candidate("Block \($0)") }
        #expect(ExploreSearch.matches(query: "block", in: many, limit: 5).count == 5)
    }

    @Test func queryWhitespaceIsTrimmed() {
        let results = ExploreSearch.matches(query: "  canteen  ", in: Self.campus)
        #expect(results.map(\.title) == ["Canteen 2"])
    }
}

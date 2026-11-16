import Foundation

extension Layout {
    /// The placed apps whose display name matches every word of `query`, best matches first. Apps inside folders
    /// count; hidden apps never match. Matching ignores case, diacritics, and punctuation.
    ///
    /// Ranks, best first:
    /// 1. The name starts with the first word, and every other word starts a word of the name.
    /// 2. Every word starts a word of the name, for example "code" in "Visual Studio Code".
    /// 3. Every word appears somewhere in the name, for example "ari" in "Safari".
    ///
    /// Apps of the same rank keep the Finder order of their names.
    public func searchResults(matching query: String, in catalog: Catalog) -> [InstalledApp] {
        let terms = SearchText.words(in: query)
        guard !terms.isEmpty else {
            return []
        }
        var ranked: [(app: InstalledApp, rank: Int)] = []
        for id in placedAppIDs where !hidden.contains(id) {
            if let app = catalog[id], let rank = SearchText.rank(of: app.displayName, terms: terms) {
                ranked.append((app, rank))
            }
        }
        return
            ranked
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank : InstalledApp.displayOrder(lhs.app, rhs.app)
            }
            .map(\.app)
    }
}

/// Text matching for search.
enum SearchText {
    /// Lowercased, without diacritics or width differences, so "Café" matches "cafe".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The normalized words of `text`, split at anything that is not a letter or a digit.
    static func words(in text: String) -> [String] {
        normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// 0, 1, or 2 as described in `Layout.searchResults(matching:in:)`, or nil when a term does not match.
    static func rank(of name: String, terms: [String]) -> Int? {
        let normalizedName = normalized(name)
        let nameWords = words(in: name)
        var everyTermStartsAWord = true
        for term in terms where !nameWords.contains(where: { $0.hasPrefix(term) }) {
            guard normalizedName.contains(term) else {
                return nil
            }
            everyTermStartsAWord = false
        }
        guard everyTermStartsAWord else {
            return 2
        }
        if let firstTerm = terms.first, normalizedName.hasPrefix(firstTerm) {
            return 0
        }
        return 1
    }
}

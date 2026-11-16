import MacStartCore
import Testing

@Suite("Catalog")
struct CatalogTests {
    @Test func sharedDisplayNamesListOnlyNamesUsedTwiceOrMore() {
        let release = appID("Tool")
        let beta = appID("Tool", in: "/Applications/Beta")
        let catalog = Catalog([app(release), app(beta), app(appID("Notes"))])

        #expect(catalog.sharedDisplayNames == ["Tool"])
    }
}

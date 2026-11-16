import MacStartCore
import Testing

@Test func logAreasMatchTheDocumentedCategories() {
    #expect(LogArea.allCases.map(\.rawValue) == ["catalog", "layout", "overlay", "hotkey"])
    #expect(LogArea.subsystem == "cc.summ.MacStart")
}

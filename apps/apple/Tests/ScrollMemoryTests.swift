import XCTest
@testable import CubbyCore

final class ScrollMemoryTests: XCTestCase {
    func testAnchorOrdersNeighborsByDistance() throws {
        let anchor = try XCTUnwrap(ScrollAnchor(rows: ["/a", "/b", "/c", "/d", "/e"], top: 1, offset: 7))
        XCTAssertEqual(anchor.paths, ["/b", "/c", "/a", "/d", "/e"])
        XCTAssertEqual(anchor.offset, 7)
        XCTAssertNil(ScrollAnchor(rows: [], top: 0, offset: 0))
        XCTAssertNil(ScrollAnchor(rows: ["/a"], top: 3, offset: 0))
    }

    func testResolveUsesTheAnchorThenTheNearestSurvivingNeighbor() {
        let anchor = ScrollAnchor(paths: ["/b", "/c", "/a"], offset: 12)
        let rows = ["/a", "/b", "/c"]
        XCTAssertEqual(anchor.resolve { rows.firstIndex(of: $0) }?.index, 1)
        XCTAssertEqual(anchor.resolve { rows.firstIndex(of: $0) }?.offset, 12)
        let withoutAnchor = ["/a", "/c"]
        XCTAssertEqual(anchor.resolve { withoutAnchor.firstIndex(of: $0) }?.index, 1)
        XCTAssertEqual(anchor.resolve { withoutAnchor.firstIndex(of: $0) }?.offset, 0)
        let onlyAbove = ["/a", "/z"]
        XCTAssertEqual(anchor.resolve { onlyAbove.firstIndex(of: $0) }?.index, 0)
        XCTAssertNil(anchor.resolve { ["/z"].firstIndex(of: $0) })
    }

    func testSavesReplacesAndClears() {
        var memory = ScrollMemory()
        memory.save(ScrollAnchor(paths: ["/a/1"], offset: 1), for: "/a")
        memory.save(ScrollAnchor(paths: ["/a/2"], offset: 2), for: "/a")
        XCTAssertEqual(memory.anchor(for: "/a"), ScrollAnchor(paths: ["/a/2"], offset: 2))
        XCTAssertEqual(memory.order, ["/a"])
        memory.save(nil, for: "/a")
        XCTAssertNil(memory.anchor(for: "/a"))
        XCTAssertEqual(memory.order, [])
    }

    func testEvictsLeastRecentlyUsed() {
        var memory = ScrollMemory()
        for index in 0..<ScrollMemory.limit {
            memory.save(ScrollAnchor(paths: ["/\(index)/x"], offset: 0), for: "/\(index)")
        }
        XCTAssertNotNil(memory.anchor(for: "/0"))
        memory.save(ScrollAnchor(paths: ["/new/x"], offset: 0), for: "/new")
        XCTAssertNotNil(memory.anchor(for: "/0"))
        XCTAssertNil(memory.anchor(for: "/1"))
        XCTAssertNotNil(memory.anchor(for: "/new"))
        XCTAssertEqual(memory.order.count, ScrollMemory.limit)
    }
}

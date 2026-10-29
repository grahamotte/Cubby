import XCTest
@testable import CubbyCore

final class SidebarProfileTests: XCTestCase {
    func testIconsAreUnique() {
        XCTAssertEqual(Set(SidebarProfile.icons).count, SidebarProfile.icons.count)
        XCTAssertEqual(SidebarProfile.icons.count, 20)
    }

    func testDecodesMissingKeysWithDefaults() throws {
        let profile = try JSONDecoder().decode(SidebarProfile.self, from: Data("{}".utf8))
        XCTAssertEqual(profile.name, "Profile")
        XCTAssertEqual(profile.icon, SidebarProfile.icons[0])
        XCTAssertTrue(profile.tree.nodes.isEmpty)
        XCTAssertNil(profile.theme)
    }

    func testRoundTripsSidebar() throws {
        let profile = SidebarProfile(name: "Work", icon: "briefcase", theme: "grove", sidebar: [SidebarNode.group("Code", [SidebarNode.folder("~/Code")])])
        let decoded = try JSONDecoder().decode(SidebarProfile.self, from: JSONStore.encode(profile))
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertEqual(decoded.icon, "briefcase")
        XCTAssertEqual(decoded.theme, "grove")
        XCTAssertEqual(decoded.tree.nodes[0].children[0].path, "~/Code")
        XCTAssertTrue(decoded.tree.nodes[0].parent === decoded.tree.root)
    }

    func testMakePicksUnusedNameAndIcon() {
        let first = SidebarProfile.make(after: [SidebarProfile.personal([])])
        XCTAssertEqual(first.name, "New Profile")
        XCTAssertEqual(first.icon, "briefcase")
        XCTAssertTrue(first.tree.nodes.isEmpty)
        let second = SidebarProfile.make(after: [SidebarProfile.personal([]), first])
        XCTAssertEqual(second.name, "New Profile 2")
        XCTAssertEqual(second.icon, "house")
        XCTAssertNil(second.theme)
        XCTAssertEqual(SidebarProfile.make(after: [], theme: "grove").theme, "grove")
    }

    func testMakeCyclesIconsWhenAllAreUsed() {
        let all = SidebarProfile.icons.map { SidebarProfile(name: $0, icon: $0) }
        XCTAssertEqual(SidebarProfile.make(after: all).icon, SidebarProfile.icons[0])
        XCTAssertEqual(SidebarProfile.make(after: all + [all[0]]).icon, SidebarProfile.icons[1])
    }

    func testRenameTrimsAndRejectsBlankOrUnchanged() {
        var profile = SidebarProfile.personal([])
        XCTAssertTrue(profile.rename(to: " Home\n"))
        XCTAssertEqual(profile.name, "Home")
        XCTAssertFalse(profile.rename(to: "Home"))
        XCTAssertFalse(profile.rename(to: "  "))
        XCTAssertEqual(profile.name, "Home")
    }
}

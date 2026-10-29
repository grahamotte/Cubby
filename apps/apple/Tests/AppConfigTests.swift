import XCTest
@testable import CubbyCore

final class AppConfigTests: XCTestCase {
    func testStandardHasFavorites() {
        let config = AppConfig.standard
        XCTAssertFalse(config.showHiddenFiles)
        XCTAssertFalse(config.showDSStoreFiles)
        XCTAssertEqual(config.visibility, .standard)
        XCTAssertEqual(config.defaultView, .standard)
        XCTAssertEqual(config.terminal, "Terminal")
        XCTAssertEqual(config.appearance, .system)
        XCTAssertEqual(config.theme, "workbench")
        XCTAssertEqual(config.profiles.map(\.name), ["Personal"])
        XCTAssertEqual(config.profile, 0)
        XCTAssertEqual(config.sidebar.nodes.map(\.name), ["Favorites"])
        XCTAssertTrue(config.sidebar.nodes[0].children.allSatisfy { $0.kind == .folder })
    }

    func testDecodesMissingKeysWithDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(config.showHiddenFiles)
        XCTAssertFalse(config.showDSStoreFiles)
        XCTAssertEqual(config.defaultView, .standard)
        XCTAssertEqual(config.profiles.map(\.name), ["Personal"])
        XCTAssertTrue(config.sidebar.nodes.isEmpty)
        XCTAssertEqual(config.terminal, "Terminal")
        XCTAssertEqual(config.appearance, .system)
        XCTAssertEqual(config.theme, ThemeLibrary.defaultID)
    }

    func testDecodesAppearanceAndTheme() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"appearance":"dark","theme":"grove"}"#.utf8))
        XCTAssertEqual(config.appearance, .dark)
        XCTAssertEqual(config.theme, "grove")
    }

    func testDecodesGalleryDefaultViewAsIcons() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"showHiddenFiles":true,"defaultView":{"mode":"gallery","iconSize":120},"theme":"grove"}"#.utf8))
        XCTAssertEqual(config.defaultView.mode, .icons)
        XCTAssertEqual(config.defaultView.iconSize, 120)
        XCTAssertTrue(config.showHiddenFiles)
        XCTAssertEqual(config.theme, "grove")
    }

    func testDecodesVisibility() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"showHiddenFiles":true,"showDSStoreFiles":true}"#.utf8))
        XCTAssertEqual(config.visibility, Visibility(showHidden: true, showDSStore: true))
        let hiddenOnly = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"showHiddenFiles":true}"#.utf8))
        XCTAssertEqual(hiddenOnly.visibility, Visibility(showHidden: true, showDSStore: false))
    }

    func testRejectsUnknownAppearance() {
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: Data(#"{"appearance":"sepia"}"#.utf8)))
    }

    func testMigratesLegacySidebarIntoPersonalProfile() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"sidebar":[{"group":"Work","items":[{"folder":"/tmp"}]}]}"#.utf8))
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Personal")
        XCTAssertEqual(config.profiles[0].icon, "person")
        XCTAssertEqual(config.sidebar.nodes[0].children[0].path, "/tmp")
    }

    func testEncodesProfilesWithoutLegacySidebar() throws {
        var config = AppConfig.standard
        config.addProfile()
        XCTAssertTrue(config.selectProfile(1))
        let json = try JSONSerialization.jsonObject(with: JSONStore.encode(config)) as? [String: Any]
        XCTAssertNil(json?["sidebar"])
        XCTAssertEqual(json?["profile"] as? Int, 1)
        XCTAssertEqual((json?["profiles"] as? [[String: Any]])?.map { $0["name"] as? String }, ["Personal", "New Profile"])
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONStore.encode(config))
        XCTAssertEqual(decoded.profile, 1)
        XCTAssertEqual(decoded.profiles[0].tree.nodes.map(\.name), ["Favorites"])
        XCTAssertTrue(decoded.sidebar.nodes.isEmpty)
    }

    func testDecodingClampsProfileAndReplacesEmptyProfiles() throws {
        let clamped = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"profiles":[{"name":"A","icon":"star","sidebar":[]},{"name":"B","icon":"moon","sidebar":[]}],"profile":7}"#.utf8))
        XCTAssertEqual(clamped.profile, 1)
        let negative = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"profiles":[{"name":"A","icon":"star","sidebar":[]}],"profile":-2}"#.utf8))
        XCTAssertEqual(negative.profile, 0)
        let empty = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"profiles":[],"sidebar":[{"group":"Old","items":[]}]}"#.utf8))
        XCTAssertEqual(empty.profiles.map(\.name), ["Personal"])
        XCTAssertEqual(empty.sidebar.nodes.map(\.name), ["Old"])
    }

    func testAddAndSelectProfiles() {
        var config = AppConfig.standard
        XCTAssertEqual(config.addProfile(), 1)
        XCTAssertEqual(config.addProfile(), 2)
        XCTAssertEqual(config.profiles.map(\.name), ["Personal", "New Profile", "New Profile 2"])
        XCTAssertEqual(config.profile, 0)
        XCTAssertTrue(config.selectProfile(2))
        XCTAssertFalse(config.selectProfile(2))
        XCTAssertFalse(config.selectProfile(3))
        XCTAssertFalse(config.selectProfile(-1))
        XCTAssertTrue(config.sidebar === config.profiles[2].tree)
    }

    func testRemoveProfileKeepsActiveProfile() {
        var config = AppConfig.standard
        config.addProfile()
        config.addProfile()
        config.selectProfile(2)
        XCTAssertTrue(config.removeProfile(at: 0))
        XCTAssertEqual(config.profile, 1)
        XCTAssertEqual(config.profiles[config.profile].name, "New Profile 2")
        XCTAssertFalse(config.removeProfile(at: 5))
        XCTAssertTrue(config.removeProfile(at: 1))
        XCTAssertEqual(config.profile, 0)
        XCTAssertEqual(config.profiles.map(\.name), ["New Profile"])
        XCTAssertFalse(config.removeProfile(at: 0))
        XCTAssertEqual(config.profiles.count, 1)
    }

    func testRemoveActiveProfileSelectsNeighbor() {
        var config = AppConfig.standard
        config.addProfile()
        config.addProfile()
        config.selectProfile(1)
        XCTAssertTrue(config.removeProfile(at: 1))
        XCTAssertEqual(config.profile, 1)
        XCTAssertEqual(config.profiles[config.profile].name, "New Profile 2")
        XCTAssertTrue(config.removeProfile(at: 1))
        XCTAssertEqual(config.profile, 0)
    }

    func testRenameAndIconChanges() {
        var config = AppConfig.standard
        XCTAssertTrue(config.renameProfile(at: 0, to: "  Home  "))
        XCTAssertEqual(config.profiles[0].name, "Home")
        XCTAssertFalse(config.renameProfile(at: 0, to: "Home"))
        XCTAssertFalse(config.renameProfile(at: 0, to: "   "))
        XCTAssertFalse(config.renameProfile(at: 3, to: "Nope"))
        XCTAssertTrue(config.setProfileIcon(at: 0, to: "house"))
        XCTAssertFalse(config.setProfileIcon(at: 0, to: "house"))
        XCTAssertFalse(config.setProfileIcon(at: 1, to: "star"))
        XCTAssertEqual(config.profiles[0].icon, "house")
    }

    func testMigratesLegacyThemeIntoProfilesAndDropsItOnSave() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"theme":"grove","profiles":[{"name":"A","icon":"star","sidebar":[]},{"name":"B","icon":"moon","theme":"sakura","sidebar":[]}],"profile":1}"#.utf8))
        XCTAssertEqual(config.profiles.map(\.theme), ["grove", "sakura"])
        XCTAssertEqual(config.theme, "sakura")
        let json = try JSONSerialization.jsonObject(with: JSONStore.encode(config)) as? [String: Any]
        XCTAssertNil(json?["theme"])
        XCTAssertEqual((json?["profiles"] as? [[String: Any]])?.map { $0["theme"] as? String }, ["grove", "sakura"])
        let legacySidebar = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"theme":"grove","sidebar":[]}"#.utf8))
        XCTAssertEqual(legacySidebar.profiles.map(\.theme), ["grove"])
        let noTheme = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"profiles":[{"name":"A","icon":"star","sidebar":[]}]}"#.utf8))
        XCTAssertEqual(noTheme.theme, ThemeLibrary.defaultID)
    }

    func testThemesArePerProfile() {
        var config = AppConfig.standard
        XCTAssertTrue(config.setTheme("grove", forProfile: 0))
        XCTAssertFalse(config.setTheme("grove", forProfile: 0))
        XCTAssertFalse(config.setTheme("grove", forProfile: 4))
        XCTAssertEqual(config.addProfile(), 1)
        XCTAssertEqual(config.themeID(at: 1), "grove")
        XCTAssertTrue(config.setTheme("sakura", forProfile: 1))
        XCTAssertEqual(config.theme, "grove")
        XCTAssertTrue(config.selectProfile(1))
        XCTAssertEqual(config.theme, "sakura")
        XCTAssertEqual(config.themeID(at: 9), ThemeLibrary.defaultID)
    }

    func testKeepsMissingThemeIDs() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"profiles":[{"name":"A","icon":"star","theme":"deleted","sidebar":[]}]}"#.utf8))
        XCTAssertEqual(config.theme, "deleted")
        XCTAssertEqual(ThemeLibrary().theme(id: config.theme).id, ThemeLibrary.defaultID)
        let json = try JSONSerialization.jsonObject(with: JSONStore.encode(config)) as? [String: Any]
        XCTAssertEqual((json?["profiles"] as? [[String: Any]])?.first?["theme"] as? String, "deleted")
    }

    func testUpdateFoldersAcrossProfiles() {
        let config = AppConfig(showHiddenFiles: false, defaultView: .standard, terminal: "Terminal", appearance: .system, theme: "workbench", profiles: [
            SidebarProfile(name: "A", icon: "star", sidebar: [SidebarNode.folder("/old/a")]),
            SidebarProfile(name: "B", icon: "moon", sidebar: [SidebarNode.group("G", [SidebarNode.folder("/old")])]),
        ])
        XCTAssertTrue(config.updateFolders(movedFrom: "/old", to: "/new"))
        XCTAssertEqual(config.profiles[0].tree.nodes[0].path, "/new/a")
        XCTAssertEqual(config.profiles[1].tree.nodes[0].children[0].path, "/new")
        XCTAssertFalse(config.updateFolders(movedFrom: "/missing", to: "/else"))
    }
}

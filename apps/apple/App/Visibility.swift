import Foundation

struct Visibility: Equatable {
    static let dsStoreName = ".DS_Store"
    static let standard = Visibility(showHidden: false, showDSStore: false)

    var showHidden: Bool
    var showDSStore: Bool

    var showsEverything: Bool {
        showHidden && showDSStore
    }

    func shows(_ item: FileItem) -> Bool {
        shows(name: item.name, isHidden: item.isHidden)
    }

    func shows(name: String, isHidden: Bool) -> Bool {
        if name == Visibility.dsStoreName { return showHidden && showDSStore }
        return showHidden || !isHidden
    }
}

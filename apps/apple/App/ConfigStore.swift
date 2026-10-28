import Foundation

final class ConfigStore {
    enum LoadResult {
        case loaded(AppConfig)
        case created(AppConfig)
        case invalid(AppConfig, String)
    }

    let paths: CubbyPaths
    private(set) var lastWritten: Data?

    init(paths: CubbyPaths) {
        self.paths = paths
    }

    func load() -> LoadResult {
        let file = paths.configFile
        guard let data = try? Data(contentsOf: file) else {
            let config = AppConfig.standard
            try? save(config)
            return .created(config)
        }
        do {
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            return .invalid(.standard, ConfigStore.describe(error))
        }
    }

    func isOwnWrite(_ data: Data?) -> Bool {
        data != nil && data == lastWritten
    }

    func save(_ config: AppConfig) throws {
        let data = try JSONStore.encode(config)
        try JSONStore.write(data, to: paths.configFile)
        lastWritten = data
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case .dataCorrupted(let context), .keyNotFound(_, let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return [path.isEmpty ? nil : path, context.debugDescription, underlying].compactMap { $0 }.joined(separator: ": ")
        @unknown default:
            return error.localizedDescription
        }
    }
}

enum JSONStore {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

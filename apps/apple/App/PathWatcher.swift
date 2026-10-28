import Foundation

@MainActor
final class PathWatcher {
    let path: String
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let latency: TimeInterval

    init(path: String, latency: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.path = path
        self.latency = latency
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
    }

    private func start() {
        source?.cancel()
        source = nil
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = self.source?.data ?? []
            if event.contains(.delete) || event.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.start() }
            }
            self.schedule()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + latency, execute: item)
    }
}

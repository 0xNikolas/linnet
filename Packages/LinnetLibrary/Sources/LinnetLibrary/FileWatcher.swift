import Foundation

public final class FileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @Sendable ([URL]) -> Void

    private var sources: [DispatchSourceFileSystemObject] = []
    private var fileDescriptors: [Int32] = []
    private let queue = DispatchQueue(label: "com.linnet.filewatcher", qos: .utility)
    private var watchedPaths: [String] = []
    private var onFilesChanged: ChangeHandler?
    private var pendingDebounce: DispatchWorkItem?

    public init() {}

    deinit {
        // Safe: deinit is called only when no other references exist
        for source in sources {
            source.cancel()
        }
    }

    public func watch(folder path: String, onChange: @escaping ChangeHandler) {
        queue.async { [self] in
            onFilesChanged = onChange
            watchedPaths.append(path)

            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return }
            fileDescriptors.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                self?.scheduleDebounce()
            }

            source.setCancelHandler {
                close(fd)
            }

            sources.append(source)
            source.resume()
        }
    }

    public func stopAll() {
        queue.async { [self] in
            pendingDebounce?.cancel()
            pendingDebounce = nil
            for source in sources {
                source.cancel()
            }
            sources.removeAll()
            fileDescriptors.removeAll()
            watchedPaths.removeAll()
        }
    }

    /// Must be called on `queue`
    private func scheduleDebounce() {
        pendingDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.scanForChanges()
        }
        pendingDebounce = work
        queue.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Must be called on `queue`
    private func scanForChanges() {
        let paths = watchedPaths
        let handler = onFilesChanged
        Task {
            var allFiles: [URL] = []
            for path in paths {
                let url = URL(filePath: path)
                let files = FolderScanner.collectAudioFiles(in: url)
                allFiles.append(contentsOf: files)
            }
            handler?(allFiles)
        }
    }
}

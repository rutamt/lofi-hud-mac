import CoreServices
import Foundation

/// Finds playable files in the music folder.
enum Library {
    /// Containers AVFoundation can decode. OGG/Opus/WMA aren't supported, so they're not counted.
    static let validExtensions: Set<String> = [
        "mp3", "m4a", "aac", "mp4", "wav", "aif", "aiff", "aifc", "caf", "flac",
    ]

    static func scan(_ musicDir: String) -> [URL] {
        let root = URL(fileURLWithPath: (musicDir as NSString).expandingTildeInPath, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker {
            if url.lastPathComponent.contains("Ignored_Lofi") {
                walker.skipDescendants()
                continue
            }
            if validExtensions.contains(url.pathExtension.lowercased()) {
                found.append(URL(fileURLWithPath: url.path))  // plain absolute URL so equality is stable
            }
        }
        return found
    }

    private static let queue = DispatchQueue(label: "com.rutamt.lofihud.scan", qos: .utility)

    /// Scan off the main thread; `completion` runs on main.
    static func scanInBackground(_ musicDir: String, completion: @escaping ([URL]) -> Void) {
        queue.async {
            let files = scan(musicDir)
            DispatchQueue.main.async { completion(files) }
        }
    }
}

/// Watches a folder tree with FSEvents and reports (coalesced) changes on the main queue.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(path: String, latency: TimeInterval = 2.0, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [expanded] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

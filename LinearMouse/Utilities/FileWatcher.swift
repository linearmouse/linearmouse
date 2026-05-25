// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreServices
import Foundation

final class FileWatcher {
    private let fileURLsProvider: () -> [URL]
    private let queue: DispatchQueue
    private let onChange: () -> Void

    private var stream: FSEventStreamRef?
    private var isRunning = false
    private var watchedRootPaths: [String] = []

    init(
        fileURLsProvider: @escaping () -> [URL],
        queue: DispatchQueue,
        onChange: @escaping () -> Void
    ) {
        self.fileURLsProvider = fileURLsProvider
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        isRunning = true
        updateStream(force: true)
    }

    func stop() {
        isRunning = false
        stopStream()
        watchedRootPaths = []
    }

    private func updateStream(force: Bool = false) {
        guard isRunning else {
            return
        }

        let rootPaths = Self.rootPaths(for: fileURLsProvider())
        guard force || rootPaths != watchedRootPaths else {
            return
        }

        stopStream()
        watchedRootPaths = rootPaths

        guard !rootPaths.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.handleEvents,
            &context,
            rootPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            watchedRootPaths = []
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)

        guard FSEventStreamStart(stream) else {
            stopStream()
            watchedRootPaths = []
            return
        }
    }

    private func stopStream() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let handleEvents: FSEventStreamCallback = { _, context, eventCount, eventPaths, eventFlags, _ in
        guard let context else {
            return
        }

        let watcher = Unmanaged<FileWatcher>
            .fromOpaque(context)
            .takeUnretainedValue()
        let eventPathPointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)

        let shouldNotify = (0 ..< eventCount).contains { index in
            let eventPath = String(cString: eventPathPointers[index])
            return watcher.shouldNotify(for: eventPath, flags: eventFlags[index])
        }

        if shouldNotify {
            watcher.onChange()
        }

        watcher.queue.async { [weak watcher] in
            watcher?.updateStream()
        }
    }

    private func shouldNotify(for eventPath: String, flags: FSEventStreamEventFlags) -> Bool {
        if Self.isRelevant(eventPath: eventPath, to: fileURLsProvider()) {
            return true
        }

        let requiresRescan = Self.hasAny(
            flags,
            [
                FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
                FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
                FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
                FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
            ]
        )
        guard requiresRescan else {
            return false
        }

        let canonicalEventPath = Self.canonicalPath(eventPath)
        return watchedRootPaths.contains {
            Self.pathsOverlap(canonicalEventPath, $0)
        }
    }

    private static func rootPaths(for fileURLs: [URL]) -> [String] {
        Array(Set(fileURLs.flatMap(rootPaths(for:)))).sorted()
    }

    private static func rootPaths(for fileURL: URL) -> [String] {
        var rootPaths: [String] = []
        let filePath = filePathPreservingLastSymlink(fileURL.path)
        let fileDirectory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let parentDirectory = fileDirectory.deletingLastPathComponent()

        if let rootPath = existingDirectory(atOrAbove: parentDirectory) {
            rootPaths.append(rootPath)
        }

        let resolvedFilePath = canonicalPath(fileURL.path)
        if resolvedFilePath != filePath {
            let resolvedDirectory = URL(fileURLWithPath: resolvedFilePath).deletingLastPathComponent()
            if let rootPath = existingDirectory(atOrAbove: resolvedDirectory) {
                rootPaths.append(rootPath)
            }
        }

        return rootPaths
    }

    private static func existingDirectory(atOrAbove url: URL) -> String? {
        var currentURL = url.standardizedFileURL

        while currentURL.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: currentURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return canonicalPath(currentURL.path)
            }
            currentURL.deleteLastPathComponent()
        }

        return "/"
    }

    private static func isRelevant(eventPath: String, to fileURLs: [URL]) -> Bool {
        let eventPath = canonicalPath(eventPath)

        return fileURLs.contains { fileURL in
            let filePath = filePathPreservingLastSymlink(fileURL.path)
            let fileDirectoryPath = canonicalPath(fileURL.deletingLastPathComponent().path)
            let parentDirectoryPath = canonicalPath(
                fileURL.deletingLastPathComponent().deletingLastPathComponent().path
            )

            if pathsOverlap(eventPath, filePath) ||
                pathsOverlap(eventPath, fileDirectoryPath) ||
                eventPath == parentDirectoryPath {
                return true
            }

            let resolvedFilePath = canonicalPath(fileURL.path)
            if resolvedFilePath != filePath {
                let resolvedDirectoryPath = canonicalPath(
                    URL(fileURLWithPath: resolvedFilePath).deletingLastPathComponent().path
                )
                return pathsOverlap(eventPath, resolvedFilePath) ||
                    eventPath == resolvedDirectoryPath
            }

            return false
        }
    }

    private static func hasAny(_ flags: FSEventStreamEventFlags, _ candidates: [FSEventStreamEventFlags]) -> Bool {
        candidates.contains {
            flags & $0 != 0
        }
    }

    private static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        isSameOrDescendant(lhs, of: rhs) || isSameOrDescendant(rhs, of: lhs)
    }

    private static func isSameOrDescendant(_ path: String, of rootPath: String) -> Bool {
        let path = path.trimmedTrailingSlashes()
        let rootPath = rootPath.trimmedTrailingSlashes()

        if rootPath == "/" {
            return path.hasPrefix("/")
        }

        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func filePathPreservingLastSymlink(_ path: String) -> String {
        let url = URL(fileURLWithPath: lexicallyStandardizedPath(path))
        let directoryPath = canonicalPath(url.deletingLastPathComponent().path)
        return URL(fileURLWithPath: directoryPath, isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
            .path
    }

    private static func canonicalPath(_ path: String) -> String {
        resolveSymlinks(in: lexicallyStandardizedPath(path), seenPaths: [])
    }

    private static func resolveSymlinks(in path: String, seenPaths: Set<String>) -> String {
        let standardizedPath = lexicallyStandardizedPath(path)
        guard standardizedPath.hasPrefix("/") else {
            return standardizedPath
        }

        let components = standardizedPath.split(separator: "/").map(String.init)
        guard !components.isEmpty else {
            return "/"
        }

        var resolvedComponents: [String] = []
        for (index, component) in components.enumerated() {
            let candidatePath = pathString(from: resolvedComponents + [component], isAbsolute: true)
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: candidatePath) else {
                resolvedComponents.append(component)
                continue
            }

            let destinationPath: String
            if destination.hasPrefix("/") {
                destinationPath = lexicallyStandardizedPath(destination)
            } else {
                let parentPath = pathString(from: resolvedComponents, isAbsolute: true)
                destinationPath = lexicallyStandardizedPath(parentPath + "/" + destination)
            }

            let remainingPath = components.dropFirst(index + 1).joined(separator: "/")
            let nextPath = remainingPath.isEmpty
                ? destinationPath
                : lexicallyStandardizedPath(destinationPath + "/" + remainingPath)

            guard !seenPaths.contains(nextPath) else {
                return standardizedPath
            }

            return resolveSymlinks(
                in: nextPath,
                seenPaths: seenPaths.union([standardizedPath])
            )
        }

        return pathString(from: resolvedComponents, isAbsolute: true)
    }

    private static func lexicallyStandardizedPath(_ path: String) -> String {
        let path = (path as NSString).expandingTildeInPath
        let isAbsolute = path.hasPrefix("/")
        var components: [String] = []

        for component in path.split(separator: "/").map(String.init) {
            switch component {
            case ".", "":
                continue
            case "..":
                if !components.isEmpty, components.last != ".." {
                    components.removeLast()
                } else if !isAbsolute {
                    components.append(component)
                }
            default:
                components.append(component)
            }
        }

        let result = pathString(from: components, isAbsolute: isAbsolute)
        if result.isEmpty {
            return isAbsolute ? "/" : "."
        }
        return result
    }

    private static func pathString(from components: [String], isAbsolute: Bool) -> String {
        let joinedComponents = components.joined(separator: "/")
        if isAbsolute {
            return joinedComponents.isEmpty ? "/" : "/" + joinedComponents
        }
        return joinedComponents
    }
}

private extension String {
    func trimmedTrailingSlashes() -> String {
        var path = self
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

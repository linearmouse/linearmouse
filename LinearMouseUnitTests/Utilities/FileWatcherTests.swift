// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class FileWatcherTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        temporaryDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("linearmouse-file-watcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory,
           FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil

        try super.tearDownWithError()
    }

    func testRelevantPathsIgnoreSiblingDirectories() throws {
        let parentDirectory = try URL(fileURLWithPath: realPath(XCTUnwrap(temporaryDirectory)), isDirectory: true)
        let watchedDirectory = parentDirectory.appendingPathComponent("config", isDirectory: true)
        let watchedFile = watchedDirectory.appendingPathComponent("linearmouse.json")

        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let relevantPaths = FileWatcher.relevantPaths(for: [watchedFile])

        XCTAssertTrue(relevantPaths.contains(watchedFile.path))
        XCTAssertTrue(relevantPaths.contains(watchedDirectory.path))
        XCTAssertTrue(relevantPaths.contains(parentDirectory.path))
        XCTAssertFalse(relevantPaths.contains(parentDirectory.appendingPathComponent("other-app/state.json").path))
        XCTAssertFalse(relevantPaths.contains(parentDirectory.appendingPathComponent("config-backup").path))
    }

    func testRelevantPathsIncludeSymlinkedConfigurationDirectory() throws {
        let parentDirectory = try URL(fileURLWithPath: realPath(XCTUnwrap(temporaryDirectory)), isDirectory: true)
        let targetDirectory = parentDirectory.appendingPathComponent("target", isDirectory: true)
        let linkedDirectory = parentDirectory.appendingPathComponent("config", isDirectory: true)

        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: targetDirectory)

        let relevantPaths = FileWatcher.relevantPaths(for: [linkedDirectory.appendingPathComponent("linearmouse.json")])

        XCTAssertTrue(relevantPaths.contains(linkedDirectory.path))
        XCTAssertTrue(relevantPaths.contains(targetDirectory.appendingPathComponent("linearmouse.json").path))
    }

    func testReportsDeletionOfHigherPriorityFile() throws {
        let directory = try XCTUnwrap(temporaryDirectory)
        let primaryFile = directory.appendingPathComponent("primary/linearmouse.json")
        let fallbackFile = directory.appendingPathComponent("fallback/linearmouse.json")

        for file in [primaryFile, fallbackFile] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "{}".write(to: file, atomically: true, encoding: .utf8)
        }

        let removedPrimaryFile = expectation(description: "Report removal of the higher-priority file")
        var didReportRemovedPrimaryFile = false

        let watcher = FileWatcher(
            fileURLsProvider: { [primaryFile, fallbackFile] },
            queue: .main
        ) {
            if !didReportRemovedPrimaryFile,
               !FileManager.default.fileExists(atPath: primaryFile.path) {
                didReportRemovedPrimaryFile = true
                removedPrimaryFile.fulfill()
            }
        }
        watcher.start()
        defer {
            watcher.stop()
        }

        try FileManager.default.removeItem(at: primaryFile)
        wait(for: [removedPrimaryFile], timeout: 5)
    }

    func testReportsChangesAfterSymlinkedDirectoryIsRetargeted() throws {
        let directory = try XCTUnwrap(temporaryDirectory)
        let firstTarget = directory.appendingPathComponent("first", isDirectory: true)
        let secondTarget = directory.appendingPathComponent("second", isDirectory: true)
        let linkedDirectory = directory.appendingPathComponent("config", isDirectory: true)
        let watchedFile = linkedDirectory.appendingPathComponent("linearmouse.json")

        for target in [firstTarget, secondTarget] {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try "{}".write(to: target.appendingPathComponent("linearmouse.json"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: firstTarget)

        let retargeted = expectation(description: "Report symlink retarget")
        let editedNewTarget = expectation(description: "Report edit in the new symlink target")
        var didReportRetarget = false
        var didReportEdit = false

        let watcher = FileWatcher(
            fileURLsProvider: { [watchedFile] },
            queue: .main
        ) {
            let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: linkedDirectory.path)
            guard destination == secondTarget.path else {
                return
            }

            if !didReportRetarget {
                didReportRetarget = true
                retargeted.fulfill()
                return
            }

            let contents = try? String(contentsOf: watchedFile, encoding: .utf8)
            if !didReportEdit, contents == "{\"edited\":true}" {
                didReportEdit = true
                editedNewTarget.fulfill()
            }
        }
        watcher.start()
        defer {
            watcher.stop()
        }

        try FileManager.default.removeItem(at: linkedDirectory)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: secondTarget)
        wait(for: [retargeted], timeout: 5)

        try "{\"edited\":true}".write(
            to: secondTarget.appendingPathComponent("linearmouse.json"),
            atomically: true,
            encoding: .utf8
        )
        wait(for: [editedNewTarget], timeout: 5)
    }

    func testReportsChangesAfterWatchedDirectoryIsRecreated() throws {
        let watchedDirectory = try XCTUnwrap(temporaryDirectory)
            .appendingPathComponent("config", isDirectory: true)
        let watchedFile = watchedDirectory.appendingPathComponent("linearmouse.json")

        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)
        try "{}".write(to: watchedFile, atomically: true, encoding: .utf8)

        let removedDirectory = expectation(description: "Report watched directory removal")
        let recreatedFile = expectation(description: "Report file write after watched directory is recreated")
        var didReportRemovedDirectory = false
        var didReportRecreatedFile = false

        let watcher = FileWatcher(
            fileURLsProvider: { [watchedFile] },
            queue: .main
        ) {
            if !didReportRemovedDirectory,
               !FileManager.default.fileExists(atPath: watchedDirectory.path) {
                didReportRemovedDirectory = true
                removedDirectory.fulfill()
                return
            }

            if didReportRemovedDirectory,
               !didReportRecreatedFile,
               FileManager.default.fileExists(atPath: watchedFile.path) {
                didReportRecreatedFile = true
                recreatedFile.fulfill()
            }
        }
        watcher.start()
        defer {
            watcher.stop()
        }

        try FileManager.default.removeItem(at: watchedDirectory)
        wait(for: [removedDirectory], timeout: 5)

        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)
        try "{\"recreated\":true}".write(to: watchedFile, atomically: true, encoding: .utf8)
        wait(for: [recreatedFile], timeout: 5)
    }

    private func realPath(_ url: URL) -> String {
        guard let path = realpath(url.path, nil) else {
            return url.path
        }
        defer {
            free(path)
        }
        return String(cString: path)
    }
}

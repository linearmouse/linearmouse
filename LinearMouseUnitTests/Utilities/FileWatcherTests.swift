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
}

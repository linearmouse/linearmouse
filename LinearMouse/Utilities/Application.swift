// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit

enum Application {
    static func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/bin/sh"
        task.environment = ["BUNDLE_PATH": path]
        task.arguments = [
            "-c",
            "while $(kill -0 $PPID 2>/dev/null); do sleep .1; done; /usr/bin/open \"$BUNDLE_PATH\" --args --show"
        ]
        do {
            try task.run()
        } catch {
            NSAlert(error: error).runModal()
        }
        NSApp.terminate(nil)
    }
}

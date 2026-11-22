// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: GAME DETECTION
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// Games count every scroll event they receive, so a glide (many small events
// per wheel click) would move a game's hotbar several steps per click. Games
// that use the mouse for looking around ("mouse capture": Minecraft and other
// GLFW, SDL or native games) hide the cursor while doing so. When the cursor
// is hidden, GlideScrollingTransformer sends one plain wheel click per notch
// instead of gliding.
//
// The check runs once per wheel click that Glide handles, never on mouse
// movement, so it costs nothing while the wheel is idle.

import Darwin

/// Tells glide scrolling when a game has captured the mouse.
enum GlideCursorCapture {
    /// The C function signature of `CGCursorIsVisible`.
    private typealias CursorIsVisibleFunction = @convention(c) () -> Int32

    /// `CGCursorIsVisible` is deprecated with no replacement, but the window
    /// server still answers it for the whole login session, so it also sees
    /// other apps hiding the cursor. It is looked up at run time, so a future
    /// SDK that removes the declaration still builds; if the function is
    /// missing, game detection simply never triggers and Glide always glides.
    private static let cursorIsVisible: CursorIsVisibleFunction? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT: search all loaded libraries
        guard let symbol = dlsym(defaultHandle, "CGCursorIsVisible") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CursorIsVisibleFunction.self)
    }()

    /// Whether the cursor is currently hidden.
    static func isCursorHidden() -> Bool {
        guard let cursorIsVisible else {
            return false
        }
        return cursorIsVisible() == 0
    }
}

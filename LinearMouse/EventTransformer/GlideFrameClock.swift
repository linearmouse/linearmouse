// MIT License
// Copyright (c) 2021-2026 LinearMouse

// GLIDE SCROLLING: THE FRAME CLOCK
//
// Part of Glide scrolling. Overview: Documentation/Glide.md
//
// Decides *when* the glide moves: exactly once per screen refresh, in step
// with the display the cursor is on. The engine (GlideScrollingEngine.swift)
// decides *how far*.
//
// Why not a plain timer? A timer drifts against the screen, so some frames
// get two scroll steps and some get none. Safari and other apps that draw
// strictly on screen refresh show that as a subtle judder. Following the
// display's own refresh signal (a "display link") gives every frame one
// evenly sized step.
//
// Contents
//   1. GlideFrameClocking     The small interface the transformer uses
//                             (start, stop, frame length), so tests can swap
//                             in a fake clock.
//   2. Setup and properties
//   3. Start and stop         Includes keeping the display link warm for a
//                             second after a glide, so the next click starts
//                             on the very next frame.
//   4. Bridge timer           Stands in for the first few frames while a
//                             sleeping display link wakes up.
//   5. Display link           Receives refresh callbacks on a background
//                             thread and hands frame times to the event thread.
//   6. Refresh grid           Snaps frame times onto an exactly regular grid,
//                             which removes ~1 ms timestamp wobble.
//   7. Refresh rate           Finds the display's true full refresh rate
//                             (60 Hz, 120 Hz ...), ignoring lowered idle rates.

import CoreGraphics
import CoreVideo
import Darwin
import Foundation

// MARK: - 1. GlideFrameClocking

/// What the glide transformer needs from a frame clock.
protocol GlideFrameClocking: AnyObject {
    /// One frame at the display's full refresh rate, in seconds. Used to place
    /// the first frame of a glide.
    var frameInterval: TimeInterval { get }
    /// Starts calling the handler once per frame.
    func start()
    /// Stops calling the handler.
    func stop()
}

// MARK: - 2. Setup and properties

/// Calls `handler` on LinearMouse's event thread once per refresh of the
/// display under the cursor, passing the time that frame will appear on
/// screen (in `ProcessInfo.systemUptime` seconds).
///
/// How a glide's frames are produced:
/// - Warm start (a glide ended less than a second ago): the display link is
///   still running, so the next refresh drives the next frame immediately.
/// - Cold start: the display link takes several frames to deliver its first
///   callback. Until it does, a timer running at the display's refresh rate
///   stands in, aiming at the same frame times the display link will use
///   (remembered from earlier glides). The hand-over is seamless.
/// - No display link at all: the timer drives every frame.
final class GlideDisplayFrameClock: GlideFrameClocking {
    /// How long the display link keeps running after the last glide ends.
    /// Clicks within this window start on the very next frame. After it, the
    /// link stops, so an idle mouse costs nothing.
    private static let idleGracePeriod: TimeInterval = 1.0

    /// Called once per frame with that frame's time.
    private let handler: (TimeInterval) -> Void
    /// The display's refresh signal. Created once, reused.
    private var displayLink: CVDisplayLink?
    /// Whether the display link is currently delivering callbacks.
    private var displayLinkRunning = false
    /// Stand-in timer for cold starts (section 4).
    private var bridgeTimer: EventThreadTimer?
    /// Whether a glide currently wants frames.
    private var isActive = false
    /// When the warm display link should be switched off.
    private var idleDeadline: TimeInterval = 0
    /// One known frame time on the display's refresh grid, kept across
    /// glides. Event thread only.
    private var gridAnchor: TimeInterval?
    /// Refresh period of the display the link is on; see `refreshPeriod()`.
    private var cachedPeriod: (display: CGDirectDisplayID, period: TimeInterval, isFixed: Bool)?
    /// Last frame time passed to `handler`. Each frame is passed only once,
    /// even when both the bridge timer and the display link offer it.
    private var lastEmittedTime: TimeInterval = 0

    /// The values below are shared between the display link's background
    /// thread and the event thread, so they are only read or written while
    /// holding `lock`.
    private let lock = NSLock()
    /// Newest frame time from the display link, waiting for the event thread.
    /// If the event thread falls behind, only the newest frame is delivered.
    private var latestFrameTime: TimeInterval?
    /// Whether a delivery to the event thread is already queued.
    private var deliveryScheduled = false
    /// How far ahead of "now" the display link's frame times are. The bridge
    /// timer aims the same distance ahead, so both agree on which frame is next.
    private var frameLead: TimeInterval = 1.0 / 60.0
    /// Shortest spacing seen between two consecutive display link frames on
    /// the current display (a cross-check for the reported refresh rate).
    private var observedMinimumInterval: TimeInterval?
    /// Previous display link frame time, for measuring that spacing.
    private var lastRawFrameTime: TimeInterval?

    /// Converts the display link's clock ticks into seconds.
    private static let secondsPerHostTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    init(handler: @escaping (TimeInterval) -> Void) {
        self.handler = handler
    }

    /// One frame at the display's full refresh rate. The reported rate is
    /// checked against the spacing actually seen between display link frames.
    /// Power saving can only ever make frames further apart, so if frames
    /// have clearly been closer together than reported, the report shows a
    /// lowered rate and the observed spacing is used instead.
    var frameInterval: TimeInterval {
        lock.lock()
        let observed = observedMinimumInterval
        lock.unlock()

        guard let reported = refreshPeriod() else {
            return observed ?? 1.0 / 60.0
        }
        if let observed, observed < reported * 0.9 {
            return observed
        }
        return reported
    }

    deinit {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        bridgeTimer?.invalidate()
    }

    // MARK: - 3. Start and stop

    /// Called when a glide begins.
    func start() {
        guard !isActive else {
            return
        }
        isActive = true

        if displayLinkRunning, let displayLink {
            // Warm start: frames are already arriving. Just make sure they
            // come from the display the cursor is on now.
            let display = Self.displayUnderCursor()
            if CVDisplayLinkGetCurrentCGDisplay(displayLink) != display {
                CVDisplayLinkSetCurrentCGDisplay(displayLink, display)
                resetGrid()
            }
            return
        }

        // Cold start: wake the display link on the display under the cursor.
        if let displayLink = makeDisplayLinkIfNeeded() {
            let display = Self.displayUnderCursor()
            if CVDisplayLinkGetCurrentCGDisplay(displayLink) != display {
                CVDisplayLinkSetCurrentCGDisplay(displayLink, display)
                resetGrid()
            }
            displayLinkRunning = CVDisplayLinkStart(displayLink) == kCVReturnSuccess
        }

        // Drive frames from the bridge timer until the display link delivers
        // (or for good, if there is no display link).
        startBridgeTimer()
    }

    /// Called when a glide ends.
    func stop() {
        guard isActive else {
            return
        }
        isActive = false
        // Keep the display link running for the grace period. The first
        // frame it delivers after the deadline switches it off
        // (see `deliverLatestFrame`).
        idleDeadline = ProcessInfo.processInfo.systemUptime + Self.idleGracePeriod
        stopBridgeTimer()
    }

    // MARK: - 4. Bridge timer

    private func startBridgeTimer() {
        guard bridgeTimer == nil else {
            return
        }
        // Ticks at the display's refresh rate.
        bridgeTimer = EventThread.shared.scheduleTimer(
            interval: frameInterval,
            repeats: true
        ) { [weak self] in
            self?.bridgeTimerFired()
        }
        // Produce the first frame right away, not one tick from now, so the
        // page starts moving on the very next screen refresh.
        bridgeTimerFired()
    }

    /// Works out which frame the display will show next, the same way the
    /// display link would, and produces movement for it.
    private func bridgeTimerFired() {
        guard isActive else {
            return
        }
        lock.lock()
        let lead = frameLead
        lock.unlock()
        emit(gridTime(nearest: ProcessInfo.processInfo.systemUptime + lead))
    }

    /// Passes a frame time to the handler, once per frame.
    private func emit(_ frameTime: TimeInterval) {
        guard frameTime > lastEmittedTime + frameInterval * 0.5 else {
            // This frame was already handled (by the other source).
            return
        }
        lastEmittedTime = frameTime
        handler(frameTime)
    }

    /// Forgets the refresh grid, for example after moving to another display.
    private func resetGrid() {
        gridAnchor = nil
        lock.lock()
        observedMinimumInterval = nil
        lastRawFrameTime = nil
        lock.unlock()
    }

    private func stopBridgeTimer() {
        bridgeTimer?.invalidate()
        bridgeTimer = nil
    }

    // MARK: - 5. Display link

    private func stopDisplayLink() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLinkRunning = false
        lock.lock()
        latestFrameTime = nil
        lock.unlock()
    }

    private func makeDisplayLinkIfNeeded() -> CVDisplayLink? {
        if let displayLink {
            return displayLink
        }

        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            return nil
        }

        // Use `outputTime`, the moment the frame will appear on screen. Those
        // times are spaced exactly one refresh apart. (`inNow`, the time of
        // the current frame, turned out to be irregular and caused uneven
        // steps.)
        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, outputTime, _, _ in
            self?.displayLinkFired(hostTime: outputTime.pointee.hostTime, firedAt: mach_absolute_time())
            return kCVReturnSuccess
        }
        displayLink = link
        return link
    }

    /// Runs on the display link's background thread, once per refresh.
    /// Records the frame and asks the event thread to handle it.
    private func displayLinkFired(hostTime: UInt64, firedAt: UInt64) {
        let frameTime = Double(hostTime) * Self.secondsPerHostTick
        // How far in the future this frame is (kept for the bridge timer).
        let lead = (frameTime - Double(firedAt) * Self.secondsPerHostTick).clamped(to: 0 ... 0.05)

        lock.lock()
        // Measure the spacing between frames (ignoring gaps that are clearly
        // not a single refresh).
        if let lastRawFrameTime {
            let interval = frameTime - lastRawFrameTime
            if interval >= 1.0 / 250.0, interval <= 1.0 / 20.0 {
                observedMinimumInterval = min(observedMinimumInterval ?? interval, interval)
            }
        }
        lastRawFrameTime = frameTime
        latestFrameTime = frameTime
        frameLead = lead
        // Queue one delivery at a time; a queued delivery always reads the
        // newest frame.
        let needsDelivery = !deliveryScheduled
        deliveryScheduled = true
        lock.unlock()

        guard needsDelivery else {
            return
        }

        let scheduled = EventThread.shared.perform { [weak self] in
            self?.deliverLatestFrame()
        }
        if !scheduled {
            // The event thread is not running; allow a retry next frame.
            lock.lock()
            deliveryScheduled = false
            lock.unlock()
        }
    }

    /// Runs on the event thread. Handles the newest display link frame.
    private func deliverLatestFrame() {
        lock.lock()
        let frameTime = latestFrameTime
        latestFrameTime = nil
        deliveryScheduled = false
        lock.unlock()

        guard displayLinkRunning, let frameTime else {
            return
        }

        guard isActive else {
            // No glide running: the link is only being kept warm. Switch it
            // off once the grace period is over.
            if ProcessInfo.processInfo.systemUptime >= idleDeadline {
                stopDisplayLink()
            }
            return
        }

        // The display link is delivering, so it takes over from the bridge.
        stopBridgeTimer()
        emit(snappedToRefreshGrid(frameTime))
    }

    // MARK: - 6. Refresh grid

    /// The frame time on the refresh grid nearest to `time`. Starts a grid at
    /// `time` if there is none yet. Used by the bridge timer.
    private func gridTime(nearest time: TimeInterval) -> TimeInterval {
        guard let anchor = gridAnchor else {
            gridAnchor = time
            return time
        }
        let period = frameInterval
        return anchor + ((time - anchor) / period).rounded() * period
    }

    /// Display link timestamps wobble by around a millisecond. In a fast
    /// glide (100+ pixels per frame) that shows as uneven steps. Snapping
    /// each frame time to an exactly regular grid removes the wobble. If a
    /// frame is far off the grid (another display, variable refresh rate),
    /// the grid is restarted from that frame.
    private func snappedToRefreshGrid(_ frameTime: TimeInterval) -> TimeInterval {
        let period = frameInterval
        guard let anchor = gridAnchor else {
            gridAnchor = frameTime
            return frameTime
        }

        let frames = ((frameTime - anchor) / period).rounded()
        let snapped = anchor + frames * period
        guard frames >= 0, abs(frameTime - snapped) <= period * 0.25 else {
            gridAnchor = frameTime
            return frameTime
        }
        return snapped
    }

    // MARK: - 7. Refresh rate

    /// One frame at the display's full refresh rate, in seconds.
    ///
    /// The display link's own figures are not reliable for this: when the
    /// screen is still, macOS can slow the display link down, and a ProMotion
    /// (variable refresh) display reports its lowered idle rate. Either made
    /// the next glide start several frames in. The display mode's refresh
    /// rate (what System Settings shows) does not change while idle, so it is
    /// used and remembered per display.
    private func refreshPeriod() -> TimeInterval? {
        guard let displayLink else {
            return nil
        }
        let display = CVDisplayLinkGetCurrentCGDisplay(displayLink)
        let cached = cachedPeriod?.display == display ? cachedPeriod : nil
        if let cached, cached.isFixed {
            return cached.period
        }

        if let mode = CGDisplayCopyDisplayMode(display), mode.refreshRate > 0 {
            let period = 1 / mode.refreshRate
            if Self.isPlausible(period) {
                cachedPeriod = (display, period, true)
                return period
            }
        }

        // Some built-in panels report no mode refresh rate. Fall back to the
        // display link's nominal period, keeping the shortest one seen so a
        // lowered idle rate is ignored.
        let nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(displayLink)
        var period = cached?.period ?? .infinity
        if nominal.timeScale > 0, nominal.flags & Int32(CVTimeFlags.isIndefinite.rawValue) == 0 {
            period = min(period, Double(nominal.timeValue) / Double(nominal.timeScale))
        }
        guard Self.isPlausible(period) else {
            return nil
        }
        cachedPeriod = (display, period, false)
        return period
    }

    /// Accepts refresh rates between 20 Hz and 250 Hz.
    private static func isPlausible(_ period: TimeInterval) -> Bool {
        period >= 1.0 / 250.0 && period <= 1.0 / 20.0
    }

    /// The display the mouse cursor is on.
    private static func displayUnderCursor() -> CGDirectDisplayID {
        guard let location = CGEvent(source: nil)?.location else {
            return CGMainDisplayID()
        }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }
        return display
    }
}

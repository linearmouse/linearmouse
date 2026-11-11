# Glide scrolling

Glide is a smooth-scrolling mode for notched mouse wheels that feels like scrolling in Chromium-based browsers. Each wheel click moves a target a fixed distance. The page glides to that target in a fixed time and stops exactly on it, with no coasting.

It sits next to the existing modes (Accelerated, Smoothed, By Lines, By Pixels) and is chosen per app and per direction like any other scrolling setting. The existing modes are unchanged.

## Contents

1. [Why a new mode](#why-a-new-mode)
2. [How it works](#how-it-works)
3. [File index](#file-index)
4. [Changes to existing files](#changes-to-existing-files)
5. [Configuration](#configuration)
6. [Design decisions](#design-decisions)
7. [Tests](#tests)
8. [Known limitations](#known-limitations)

## Why a new mode

Smoothed mode is momentum-based. Each wheel click adds speed to a scroll that is already moving, and the scroll coasts until the speed fades. With a notched wheel this feels floaty, and quick clicks stack up, so it is hard to stop where you mean to. Tuning response, speed, acceleration and inertia changes how strong the effect is, but not the model itself.

Chromium animates mouse wheel scrolling differently: each click moves a destination, and the page animates to it over 100 to 200 ms. Glide uses that destination-based model.

## How it works

```
mouse wheel click
      │
      ▼
GlideScrollingTransformer ── trackpad / Magic Mouse / other axis ──▶ passed on unchanged
      │
      ├─ cursor hidden (a game captured the mouse) ──▶ one plain wheel click per notch
      │
      ▼
GlideScrollingEngine: target += lines × lineHeight
      │
      ▼
GlideDisplayFrameClock: once per screen refresh
      │
      ▼
engine.advance(to: frame time) → this frame's distance
      │
      ▼
one plain continuous pixel scroll event (no scroll or momentum phase)
```

1. **A wheel click arrives.** The transformer swallows it and tells the engine to move the target one click further (lines × line height pixels).
2. **The engine plans the glide.** It animates from the current position to the target along an ease-out curve over the glide duration. If the page is already moving, the new glide starts at the current speed, so clicks merge into one smooth motion.
3. **Once per screen refresh**, the frame clock asks the engine how far the page should move for that frame. Timing follows the display the cursor is on (60 Hz, 120 Hz ProMotion, and so on).
4. **The transformer posts that distance** as a small, plain continuous scroll event. Apps scroll by exactly that amount and add nothing of their own.
5. **The glide ends exactly on the target.** The total posted always equals clicks × distance per click.

## File index

All Glide code lives in new files. Each file starts with a short contents list.

| File | What it does |
| --- | --- |
| `LinearMouse/EventTransformer/GlideScrollingTransformer.swift` | Plugs Glide into the event pipeline: takes wheel clicks in, posts one scroll event per frame out, and handles game detection. |
| `LinearMouse/EventTransformer/GlideScrollingEngine.swift` | The animation math only: the easing curve, the per-axis target and timing, and the vertical/horizontal pair. No events or timers, so it is easy to test. |
| `LinearMouse/EventTransformer/GlideFrameClock.swift` | Calls the transformer once per screen refresh using a display link, with a stand-in timer while the display link wakes up. Works out the display's true refresh rate. |
| `LinearMouse/EventTransformer/GlideCursorCapture.swift` | Tells whether the cursor is hidden, which is how games capture the mouse. |
| `LinearMouse/Model/Configuration/Scheme/Scrolling/Glide.swift` | The `scrolling.glide` settings: values, defaults, ranges, and how per-app schemes override single values. |
| `LinearMouse/UI/ScrollingSettings/GlideScrollingSection.swift` | The Glide panel in the Scrolling settings. |
| `LinearMouse/UI/ScrollingSettings/ScrollingSettingsState+Glide.swift` | Connects that panel to the configuration. |
| `LinearMouseUnitTests/EventTransformer/GlideScrollingTests.swift` | Unit tests for the curve, the engine, the transformer and frame timing. |

## Changes to existing files

The existing files only get small, marked connection points. Search for "Glide scrolling" to find each one.

| File | Change |
| --- | --- |
| `EventTransformerManager.swift` | Builds the glide settings for the route. Turns Smoothed off on axes where Glide is on. Adds `GlideScrollingTransformer` at the same point in the pipeline as `SmoothedScrollingTransformer`. Treats glide axes like smoothed ones for line/pixel distance, acceleration, speed, modifier keys and the high-resolution wheel normalizer (`smoothed:` became `animated:` in `highResolutionWheelNormalizerMode`). |
| `Scrolling.swift` | Adds the `glide` property and merges it. |
| `ScrollingSettingsState.swift` | Adds "Glide" to the scrolling mode picker and switches between Glide and the other modes. |
| `ScrollingModeSection.swift` | Shows the Glide panel when Glide is selected. |
| `Documentation/Configuration.d.ts`, `Configuration.json`, `Configuration.md` | Document `scrolling.glide`. `Configuration.json` was edited by hand to match `Configuration.d.ts`; running `npm run generate:json-schema` should produce the same result. |

## Configuration

```json
"scrolling": {
  "glide": {
    "lines": 3,
    "lineHeight": 10,
    "duration": 180,
    "curve": "easeOutCubic",
    "gameDetection": true
  }
}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | `false` turns off a glide setting inherited from a broader scheme. |
| `lines` | `3` | Lines per wheel click (0 to 20). |
| `lineHeight` | `10` | Pixels per line (1 to 100). macOS uses about 10; Chromium uses 40. |
| `duration` | `180` | Milliseconds from the latest click until the glide stops (30 to 1000). |
| `curve` | `"easeOutCubic"` | `easeOutQuart`, `easeOutCubic`, `easeOut` or `easeInOut`. |
| `gameDetection` | `true` | While the cursor is hidden, send one plain wheel click per notch instead of gliding. |

Values merge field by field across schemes, so an app scheme can change only `lineHeight` and inherit the rest. Like the other values, `glide` can be set separately for `vertical` and `horizontal`. When Glide and Smoothed are both enabled for a direction, Glide wins.

## Design decisions

**Destination-based, like Chromium.** Each click moves a target; the page animates to it and stops. A click during a glide keeps the current speed (the new segment starts at the page's current speed), as Chromium's `ScrollOffsetAnimationCurve::UpdateTarget` does. A small floor (a quarter of the curve's starting speed) keeps a click in the slow tail of a glide responsive. A click in the opposite direction drops the unfinished distance.

**One curve formula for every preset.** `f(s) = 1 − (1 − s)³ · (1 + (3 − a) · s)`. The parameter `a` is the starting speed (4 = easeOutQuart, 3 = easeOutCubic, 0 = starts from standstill). The curve always lands with zero speed, and it never moves backwards for any `a` from 0 to 4. That is what lets a new click start the curve at the page's current speed without overshooting.

**Plain continuous events, no phases.** Glide posts pixel scroll events with no scroll phase, no momentum phase and no gesture companion events. Apps then treat them as simple precise scrolling and do not add their own momentum or rubber-band behaviour.

**Distance in lines, counted per physical notch.** One plain wheel event counts as one notch, exactly like line mode, so macOS wheel acceleration does not change the glide distance. High-resolution wheels are counted back into whole notches with the existing `LogitechHighResolutionWheelScrollCounter`.

**Exact fractional output.** The fixed-point delta field carries the exact distance, including fractions of a pixel, which AppKit apps and Safari read for smooth endings. The point delta field carries whole pixels with the remainder carried to the next frame, for apps that only read whole pixels (Chromium). Nothing is lost on either path.

**Synced to the display's refresh.** A free-running timer drifts against the display, so some frames get two steps and some none. That shows as subtle judder, most visibly in Safari. Glide runs from a display link on the display under the cursor. Refinements made while testing on a 60 Hz external display and a 120 Hz ProMotion MacBook:

- Frames are sampled at the display link's `outputTime`. Its spacing is exactly one refresh; `inNow` was noticeably irregular.
- Frame times are snapped to an exact refresh grid, which removes about 1 ms of timestamp wobble that showed in fast glides.
- A glide from rest starts exactly one frame before its first sampled frame, and a click between frames retargets from the last frame shown. Every frame then gets a full, even step.
- A stopped display link takes several frames to deliver its first callback. A timer at the display's refresh rate stands in, aiming at the same frame times (remembered from earlier glides), and the display link stays running for one second after a glide so the next click starts on the next frame.
- The refresh rate comes from the display mode (`CGDisplayMode.refreshRate`), cached per display, and is cross-checked against observed frame spacing. The display link's measured and nominal periods both reported lowered rates while the screen was idle (callback throttling, and ProMotion's variable refresh), which made the next glide start several frames in.

**Game detection.** Games count every scroll event, so a glide (many events per click) moves a hotbar several steps per click. Games that capture the mouse for mouse-look hide the cursor, so Glide checks `CGCursorIsVisible` once per wheel click it handles (never on mouse movement). When the cursor is hidden, it sends one plain wheel click per notch instead. `CGCursorIsVisible` is deprecated without a replacement, so it is looked up at run time; if it is ever removed, detection quietly turns off. Tested with Minecraft: hidden while playing (one click per notch), visible in menus (gliding), switching instantly.

**Battery.** No work happens while the wheel is idle. The display link only runs during a glide plus one second, and the cursor check only runs on wheel clicks.

## Tests

`GlideScrollingTests.swift` covers the curve, distances, timing, retargeting, reversal, event output (plain continuous events, no phases), trackpad pass-through, game detection, and frame-to-frame evenness. Time is driven by hand with a fake clock, so the tests are deterministic and need no display. Run them with ⌘U in Xcode or `make test`.

Manual testing so far: Safari, Mail, Finder, Notes and Chromium-based apps on a 60 Hz Studio Display and a 120 Hz ProMotion MacBook Pro display; Minecraft through Prism Launcher and Modrinth for game detection. Step sizes were checked in the `GlideScrolling` debug log: single clicks produce the identical sequence every time, and glides start and end smoothly on both displays.

## Known limitations

- **The first scroll on a display in a session** may have one uneven frame, while Glide learns that display's refresh timing.
- **Apps decide how much a pixel of scrolling is worth.** Most Mac apps and browsers scroll one pixel per pixel. GLFW-based games (Minecraft and many others) count 10 pixels as one notch, so their menus scroll much further for the same setting. A per-app scheme with a smaller `lineHeight` (for example 1 line × 10 px = exactly one notch) fixes this.
- **Games that keep the cursor visible** are not detected and still need a line-mode scheme of their own.
- **Localization:** the new settings labels are English only so far.
- **`CVDisplayLink` is deprecated** from macOS 15 in favour of `NSScreen.displayLink` / `CADisplayLink` (macOS 14+). It still works, and it is needed for LinearMouse's macOS 10.15 deployment target; switching to the newer API on macOS 14+ could be a follow-up.

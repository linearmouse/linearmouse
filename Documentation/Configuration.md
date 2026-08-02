# Configuration

The LinearMouse configuration is stored in `~/.config/linearmouse/linearmouse.json`.

If the configuration file does not exist, LinearMouse will create an empty configuration automatically.

> **Note**  
> It's preferable to use the GUI to alter settings rather than manually updating configuration
> unless you want to use advanced features.

> **Note**  
> JSON5 is not supported yet. Writing comments in configuration will raise a parsing error.

## Get started

Here is a simple example of LinearMouse configuration.

```json
{
  "$schema": "https://app.linearmouse.org/schema/0.7.2",
  "schemes": [
    {
      "if": {
        "device": {
          "category": "mouse"
        }
      },
      "scrolling": {
        "reverse": {
          "vertical": true
        }
      }
    }
  ]
}
```

This configuration reverses the vertical scrolling direction for any mouse connected to your device.

## JSON Schema

As you can see, `$schema` defines the JSON schema of the LinearMouse configuration, which enables
autocompletion in editors like VS Code.

SON schemas are published for each LinearMouse version. Backward compatibility is guaranteed for
the same major versions.

## Schemes

A scheme is a collection of settings that are activated in specified circumstances.

For example, in [get started](#get-started), we defined a scheme. The `if` field instructs
LinearMouse to activate this scheme only when the active device is a mouse:

```json
{
  "if": {
    "device": {
      "category": "mouse"
    }
  }
}
```

And the `scrolling` field in this scheme defines the scrolling behaviors, with
`"reverse": { "vertical": true }` reversing the vertical scrolling direction:

```json
{
  "scrolling": {
    "reverse": {
      "vertical": true
    }
  }
}
```

## Smoothed scrolling

`scrolling.smoothed` enables a phase-aware scrolling curve that can be tuned separately for
vertical and horizontal scrolling. You can choose a preset such as `easeIn`, `easeOut`,
`easeInOut`, `quadratic`, `cubic`, `easeOutCubic`, `easeInOutCubic`, `quartic`,
`easeOutQuartic`, `easeInOutQuartic`, `smooth`, or `custom`, then fine-tune `response`,
`speed`, `acceleration`, and `inertia` as needed.

Set `enabled` to `false` to explicitly disable an inherited smoothed scrolling configuration for a
direction.

Set `bouncing` to `false` to avoid rubber-band overscroll when smoothed scrolling emits synthetic
continuous scroll events. This keeps the smoothed momentum tail, but sends it without scroll
phase/momentum phase markers so apps are less likely to treat it like a trackpad gesture.

For example, to use a smoother scrolling profile for a mouse:

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "category": "mouse"
        }
      },
      "scrolling": {
        "smoothed": {
          "enabled": true,
          "preset": "easeInOut",
          "response": 0.45,
          "speed": 1,
          "acceleration": 1.2,
          "inertia": 0.65,
          "bouncing": false
        }
      }
    }
  ]
}
```

If you want different tuning for each direction, provide `vertical` and `horizontal` values under
`smoothed`.

## Click debouncing

`buttons.clickDebouncing` filters electrical chatter from worn or noisy mouse switches. Existing
configurations continue to use the `legacy` mode when `mode` is omitted.

The experimental `libinput` mode tracks press and release pairs with a state machine. Like
libinput, it uses a fixed 25 ms bounce window and a fixed 12 ms spurious-release window. It may
delay a suspicious release briefly, but it preserves the final release so applications do not
remain in a stuck dragging or resizing state.

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "category": "mouse"
        }
      },
      "buttons": {
        "clickDebouncing": {
          "mode": "libinput",
          "timeout": 25
        }
      }
    }
  ]
}
```

`timeout` must be greater than zero to enable the feature. Its numeric value and
`resetTimerOnMouseUp` apply only to `legacy` mode. The `buttons` list also applies only to
`legacy` mode; `libinput` mode always uses its fixed windows and covers all standard mouse buttons.

## Device matching

Vendor ID and product ID can be provided to match a specific device.

You may find these values in About This Mac → System Report... → Bluetooth / USB.

For example, to configure pointer speed of my Logitech mouse and Microsoft mouse respectively,
I would create two schemes and specify the vendor ID and product ID:

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "vendorID": "0x046d",
          "productID": "0xc52b"
        }
      },
      "pointer": {
        "acceleration": 0,
        "speed": 0.36
      }
    },
    {
      "if": {
        "device": {
          "vendorID": "0x045e",
          "productID": "0x0827"
        }
      },
      "pointer": {
        "acceleration": 0,
        "speed": 0.4
      }
    }
  ]
}
```

Then, the pointer speed of my Logitech mouse and Microsoft mouse will be set to 0.36 and 0.4
respectively.

### Unsetting values

LinearMouse supports a special "unset" value to explicitly restore settings back to their system or
device defaults. This differs from omitting a field, which keeps the previously merged value.

Currently, "unset" is supported for pointer acceleration and speed.

```json
{
  "schemes": [
    {
      "if": {
        "device": { "category": "mouse" }
      },
      "pointer": { "acceleration": "unset", "speed": "unset" }
    }
  ]
}
```

## App matching

App bundle ID can be provided to match a specific app.

For example, to modify the pointer acceleration in Safari for my Logitech mouse:

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "vendorID": "0x046d",
          "productID": "0xc52b"
        },
        "app": "com.apple.Safari"
      },
      "pointer": {
        "acceleration": 0.5
      }
    }
  ]
}
```

Or, to disable reverse scrolling in Safari for all devices:

```json
{
  "schemes": [
    {
      "if": {
        "app": "com.apple.Safari"
      },
      "scrolling": {
        "reverse": {
          "vertical": false,
          "horizontal": false
        }
      }
    }
  ]
}
```

By default, LinearMouse checks the app bundle ID of the frontmost process. However, in some
circumstances, a program might not be placed in a specific application bundle. In that case, you
may specify the app bundle ID of the parent process or the process group of the frontmost process
by specify `parentApp` and `groupApp`.

For example, to match the Minecraft (a Java process) launched by PolyMC:

```json
{
  "schemes": [
    {
      "if": {
        "parentApp": "org.polymc.PolyMC"
      }
    }
  ]
}
```

Or, to match the whole process group:

```json
{
  "schemes": [
    {
      "if": {
        "groupApp": "org.polymc.PolyMC"
      }
    }
  ]
}
```

### Process (binary) matching

Some programs do not have a stable or any bundle identifier. You can match by the frontmost process's executable instead.

- processName: Match by executable name (case-sensitive). Example:

```json
{
  "schemes": [
    {
      "if": {
        "processName": "wezterm"
      },
      "scrolling": { "reverse": false }
    }
  ]
}
```

- processPath: Match by absolute executable path (case-sensitive). Example:

```json
{
  "schemes": [
    {
      "if": {
        "processPath": "/Applications/WezTerm.app/Contents/MacOS/WezTerm"
      },
      "pointer": { "acceleration": 0.4 }
    }
  ]
}
```

Notes
- processName/processPath compare exactly; no wildcard or regex.
- Matching is against the frontmost application process (NSRunningApplication); child processes inside a terminal are not detected as the frontmost process.
- You can still combine with device and display conditions.

## Display Matching

Display name can be provided to match a specific display.

For example, to modify the pointer acceleration on DELL P2415Q:

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "vendorID": "0x046d",
          "productID": "0xc52b"
        },
        "display": "DELL P2415Q"
      },
      "pointer": {
        "acceleration": 0.5
      }
    }
  ]
}
```

## Schemes merging and multiple `if`s

If multiple schemes are activated at the same time, they will be merged in the order of their
definitions.

Additionally, if multiple `if`s are specified, the scheme will be activated as long as any of them
is satisfied.

For example, the configuration above can alternatively be written as:

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "vendorID": "0x046d",
            "productID": "0xc52b"
          }
        },
        {
          "device": {
            "vendorID": "0x045e",
            "productID": "0x0827"
          }
        }
      ],
      "pointer": {
        "acceleration": 0
      }
    },
    {
      "if": {
        "device": {
          "vendorID": "0x046d",
          "productID": "0xc52b"
        }
      },
      "pointer": {
        "speed": 0.36
      }
    },
    {
      "if": {
        "device": {
          "vendorID": "0x045e",
          "productID": "0x0827"
        }
      },
      "pointer": {
        "speed": 0.4
      }
    }
  ]
}
```

Or, with fewer lines but more difficult to maintain:

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "vendorID": "0x046d",
            "productID": "0xc52b"
          }
        },
        {
          "device": {
            "vendorID": "0x045e",
            "productID": "0x0827"
          }
        }
      ],
      "pointer": {
        "acceleration": 0,
        "speed": 0.36
      }
    },
    {
      "if": {
        "device": {
          "vendorID": "0x045e",
          "productID": "0x0827"
        }
      },
      "pointer": {
        "speed": 0.4
      }
    }
  ]
}
```

## Button mappings

Button mappings is a list that allows you to assign actions to buttons or scroll wheels.
For example, to open Launchpad when the wheel button is clicked, or to switch spaces when
<kbd>command + back</kbd> or <kbd>command + forward</kbd> is clicked.

### Basic example

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "category": "mouse"
          }
        }
      ],
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "button": 2 }
            },
            "outcomes": {
              "shortPress": "launchpad"
            }
          }
        ]
      }
    }
  ]
}
```

In this example, the wheel button is bound to open Launchpad.

`"input": { "button": 2 }` denotes the auxiliary button, which is usually the wheel button.

The following table lists all the buttons:

| Button | Description                                                      |
| ------ | ---------------------------------------------------------------- |
| 0      | Primary button, usually the left button.                         |
| 1      | Secondary button, usually the right button.                      |
| 2      | Auxiliary button, usually the wheel button or the middle button. |
| 3      | The fourth button, typically the back button.                    |
| 4      | The fifth button, typically the forward button.                  |
| 5-31   | Other buttons.                                                   |

`{ "action": { "run": "open -a Launchpad" } }` assigns a shell command `open -a LaunchPad` to
the button. When the button is clicked, the shell command will be executed.

### Advanced triggers

The structured `trigger` format supports chords, long presses, swipes, pressed/released action
lifecycles, and a wheel gesture while buttons are held. Existing flat `button` and `scroll` mappings
remain accepted and are migrated to the structured representation when the configuration is loaded.

Timing and movement thresholds are global LinearMouse policy rather than values stored in each
mapping. The current policy uses an 80 ms chord window, a 500 ms long-press duration, a 50-point
swipe threshold, and a 40-point perpendicular dead zone. When several structured outcomes share a
trigger, they belong in the same `outcomes` object:

```json
{
  "trigger": {
    "input": { "button": 4 },
    "modifiers": ["command"]
  },
  "outcomes": {
    "shortPress": "missionControl",
    "longPress": "launchpad",
    "swipe": {
      "left": "missionControl.spaceLeft",
      "right": "missionControl.spaceRight"
    }
  }
}
```

Additional buttons in `simultaneous` form an unordered chord. The most specific completed chord
wins over a mapping for one of its individual buttons:

```json
{
  "trigger": {
    "input": { "button": 0 },
    "simultaneous": [1]
  },
  "outcomes": {
    "shortPress": "showDesktop"
  }
}
```

Use `whileHeld` for an ordered combination or for button-plus-wheel. In the recorder, keep the first
button held until the prompt changes to **Then press another button**, then press the trigger button;
the result is shown as `Hold A → B`. A wheel is an instantaneous input, so it has one `action` and
cannot have long-press or swipe outcomes:

```json
{
  "trigger": {
    "input": { "wheel": "up" },
    "whileHeld": [4],
    "modifiers": ["option"]
  },
  "action": "media.volumeUp"
}
```

Use a `press` outcome when an action must begin before release. Its behavior can perform once,
repeat according to the system keyboard repeat settings, hold keyboard keys, or remap the complete
down/drag/up stream of a physical mouse button:

```json
{
  "trigger": {
    "input": { "button": 4 }
  },
  "outcomes": {
    "press": {
      "action": { "keyPress": ["command"] },
      "behavior": "hold"
    }
  }
}
```

`press` commits as soon as its trigger resolves, so it cannot be combined with `shortPress`,
`longPress`, or `swipe` in the same mapping. The GUI exposes the applicable behaviors according to
the selected action. `remap` is available only for a single physical mouse-button trigger.

If a mapping defines only a long press, swipe, or incomplete chord, an ordinary click is delayed
briefly and then passed through unchanged when the configured gesture does not match.

Matching is deterministic: exact modifiers and `whileHeld` requirements are filtered first, then
the most specific completed chord wins. A swipe or long press commits as soon as its global
threshold is reached; otherwise `shortPress` runs on release. Once one outcome commits, the other
outcomes for that press are suppressed.

Legacy mappings are normalized during decoding and use the same recognizer and action executor as
structured mappings. A normal legacy action becomes `shortPress`; `repeat`, keyboard `hold`, and
physical mouse-button swaps become `press` outcomes with the corresponding behavior; legacy scroll
mappings become wheel triggers. Saving the configuration writes the migrated structured form.

### Modifier keys

In this example, <kbd>command + forward</kbd> is bound to open Mission Control.

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "category": "mouse"
          }
        }
      ],
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "button": 4 },
              "modifiers": ["command"]
            },
            "outcomes": {
              "shortPress": "missionControl"
            }
          }
        ]
      }
    }
  ]
}
```

`"modifiers": ["command"]` denotes that <kbd>command</kbd> should be pressed.

You can specify `shift`, `option` and `control` as well.

### Switch spaces (desktops) with the <kbd>command + back</kbd> and <kbd>command + forward</kbd>

`missionControl.spaceLeft` and `missionControl.spaceRight` can be used to move left and right a space.

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "category": "mouse"
          }
        }
      ],
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "button": 3 },
              "modifiers": ["command"]
            },
            "outcomes": {
              "shortPress": "missionControl.spaceLeft"
            }
          },
          {
            "trigger": {
              "input": { "button": 4 },
              "modifiers": ["command"]
            },
            "outcomes": {
              "shortPress": "missionControl.spaceRight"
            }
          }
        ]
      }
    }
  ]
}
```

> **Note**  
> You will have to grant an additional permission to allow LinearMouse to simulate keys.

### Key repeat

With a `press` outcome whose behavior is `repeat`, actions are repeated until the trigger is
released.

In this example, <kbd>option + back</kbd> and <kbd>option + forward</kbd> is bound to volume down
and volume up.

If you hold <kbd>option + back</kbd>, the volume will continue to decrease.

> **Note**  
> If you disabled key repeat in System Settings, the action runs once on release instead.
> If you change key repeat rate or delay until repeat in System Settings, you have to restart
> LinearMouse to take effect.

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "category": "mouse"
          }
        }
      ],
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "button": 4 },
              "modifiers": ["option"]
            },
            "outcomes": {
              "press": {
                "action": "media.volumeUp",
                "behavior": "repeat"
              }
            }
          },
          {
            "trigger": {
              "input": { "button": 3 },
              "modifiers": ["option"]
            },
            "outcomes": {
              "press": {
                "action": "media.volumeDown",
                "behavior": "repeat"
              }
            }
          }
        ]
      }
    }
  ]
}
```

### Hold keyboard shortcuts while pressed

With a `press` outcome whose behavior is `hold`, keyboard shortcut actions stay pressed for as long
as the trigger is held.

This is different from `repeat`: `repeat` keeps sending the shortcut, while `hold` sends key down
when the trigger resolves and key up when it is released.

This is useful for apps that expect a real held key, such as timeline scrubbing or temporary tools.

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "category": "mouse"
        }
      },
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "button": 3 }
            },
            "outcomes": {
              "press": {
                "action": {
                  "keyPress": ["c"]
                },
                "behavior": "hold"
              }
            }
          }
        ]
      }
    }
  ]
}
```

### Volume up and down with <kbd>option + scrollUp</kbd> and <kbd>option + scrollDown</kbd>

Use a wheel trigger to map scroll impulses to specific actions.

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "category": "mouse"
          }
        }
      ],
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "wheel": "up" },
              "modifiers": ["option"]
            },
            "action": "media.volumeUp"
          },
          {
            "trigger": {
              "input": { "wheel": "down" },
              "modifiers": ["option"]
            },
            "action": "media.volumeDown"
          }
        ]
      }
    }
  ]
}
```

### Swap back and forward buttons

```json
{
  "schemes": [
    {
      "if": [
        {
          "device": {
            "category": "mouse"
          }
        }
      ],
      "buttons": {
        "mappings": [
          {
            "trigger": {
              "input": { "button": 3 }
            },
            "outcomes": {
              "press": {
                "action": "mouse.button.forward",
                "behavior": "remap"
              }
            }
          },
          {
            "trigger": {
              "input": { "button": 4 }
            },
            "outcomes": {
              "press": {
                "action": "mouse.button.back",
                "behavior": "remap"
              }
            }
          }
        ]
      }
    }
  ]
}
```

### Action sheet

#### Simple actions

A simple action is an action without any parameters.

```json
{
  "action": "<action>"
}
```

`<action>` could be one of:

| Action                      | Description                           |
| --------------------------- | ------------------------------------- |
| `auto`                      | Do not modify the button behavior.    |
| `none`                      | Prevent the button events.            |
| `missionControl`            | Mission Control.                      |
| `missionControl.spaceLeft`  | Mission Control: Move left a space.   |
| `missionControl.spaceRight` | Mission Control: Move right a space.  |
| `appExpose`                 | App Exposé.                           |
| `launchpad`                 | Launchpad.                            |
| `showDesktop`               | Show desktop.                         |
| `showDesktop`               | Show desktop.                         |
| `lookUpAndDataDetectors`    | Look up & data detectors.             |
| `smartZoom`                 | Smart zoom.                           |
| `display.brightnessUp`      | Display: Brightness up.               |
| `display.brightnessDown`    | Display: Brightness down.             |
| `media.volumeUp`            | Media: Volume up.                     |
| `media.volumeDown`          | Media: Volume down.                   |
| `media.mute`                | Media: Toggle mute.                   |
| `media.playPause`           | Media: Play / pause.                  |
| `media.next`                | Media: Next.                          |
| `media.previous`            | Media: Previous.                      |
| `media.fastForward`         | Media: Fast forward.                  |
| `media.rewind`              | Media: Rewind.                        |
| `keyboard.brightnessUp`     | Keyboard: Brightness up.              |
| `keyboard.brightnessDown`   | Keyboard: Brightness down.            |
| `mouse.wheel.scrollUp`      | Mouse: Wheel: Scroll up.              |
| `mouse.wheel.scrollDown`    | Mouse: Wheel: Scroll down.            |
| `mouse.wheel.scrollLeft`    | Mouse: Wheel: Scroll left.            |
| `mouse.wheel.scrollRight`   | Mouse: Wheel: Scroll right.           |
| `mouse.button.left`         | Mouse: Button: Act as left button.    |
| `mouse.button.middle`       | Mouse: Button: Act as middle button.  |
| `mouse.button.right`        | Mouse: Button: Act as right button.   |
| `mouse.button.back`         | Mouse: Button: Act as back button.    |
| `mouse.button.forward`      | Mouse: Button: Act as forward button. |

#### Run shell commands

```json
{
  "action": {
    "run": "<command>"
  }
}
```

The `<command>` will be executed with bash.

#### Scroll a certain distance

##### Scroll up 2 lines

```json
{
  "action": {
    "mouse.wheel.scrollUp": 2
  }
}
```

##### Scroll left 32 pixels

```json
{
  "action": {
    "mouse.wheel.scrollLeft": "32px"
  }
}
```

#### Press keyboard shortcuts

```json
{
  "action": {
    "keyPress": ["shift", "command", "4"]
  }
}
```

To see the full list of keys, please refer to [Configuration.d.ts#L652](Configuration.d.ts#L652).

#### Numpad keys support

LinearMouse supports all numpad keys for keyboard shortcuts:

- Number keys: `numpad0`, `numpad1`, `numpad2`, `numpad3`, `numpad4`, `numpad5`, `numpad6`, `numpad7`, `numpad8`, `numpad9`
- Operator keys: `numpadPlus`, `numpadMinus`, `numpadMultiply`, `numpadDivide`, `numpadEquals`
- Function keys: `numpadEnter`, `numpadDecimal`, `numpadClear`

Example usage:
```json
{
  "action": {
    "keyPress": ["numpad5"]
  }
}
```

## Pointer settings

### Redirects to scroll

The `redirectsToScroll` property allows you to redirect pointer movements to scroll events. This is useful for scenarios where you want mouse movements to control scrolling instead of cursor positioning.

```json
{
  "schemes": [
    {
      "if": {
        "device": {
          "category": "mouse"
        }
      },
      "pointer": {
        "redirectsToScroll": true
      }
    }
  ]
}
```

When `redirectsToScroll` is set to `true`, horizontal mouse movements will generate horizontal scroll events, and vertical mouse movements will generate vertical scroll events.

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
            "button": 2,
            "action": "launchpad"
          }
        ]
      }
    }
  ]
}
```

In this example, the wheel button is bound to open Launchpad.

`"button": 2` denotes the auxiliary button, which is usually the wheel button.

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
            "button": 4,
            "command": true,
            "action": "missionControl"
          }
        ]
      }
    }
  ]
}
```

`"command": true` denotes that <kbd>command</kbd> should be pressed.

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
            "button": 3,
            "command": true,
            "action": "missionControl.spaceLeft"
          },
          {
            "button": 4,
            "command": true,
            "action": "missionControl.spaceRight"
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

With `repeat: true`, actions will be repeated until the button is up.

In this example, <kbd>option + back</kbd> and <kbd>option + forward</kbd> is bound to volume down
and volume up.

If you hold <kbd>option + back</kbd>, the volume will continue to decrease.

> **Note**  
> If you disabled key repeat in System Settings, `repeat: true` will not work.
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
            "button": 4,
            "repeat": true,
            "option": true,
            "action": "media.volumeUp"
          },
          {
            "button": 3,
            "repeat": true,
            "option": true,
            "action": "media.volumeDown"
          }
        ]
      }
    }
  ]
}
```

### Volume up and down with <kbd>option + scrollUp</kbd> and <kbd>option + scrollDown</kbd>

`scroll` can be specified instead of `button` to map scroll events to specific actions.

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
            "scroll": "up",
            "option": true,
            "action": "media.volumeUp"
          },
          {
            "scroll": "down",
            "option": true,
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
            "button": 3,
            "action": "mouse.button.forward"
          },
          {
            "button": 4,
            "action": "mouse.button.back"
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

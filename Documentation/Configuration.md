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
  "$schema": "https://app.linearmouse.org/schema/0.7.1",
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

Button mappings is a list that allows you to assign actions to buttons. For example, to open
Launchpad when the back button is clicked, or to open Mission Control when <kbd>command</kbd> +
the forward button is clicked.

### Open Launchpad when the back button is clicked

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
            "action": {
              "run": "open -a Launchpad"
            }
          }
        ]
      }
    }
  ]
}
```

'"button": 3' denotes the fourth button, which is typically the back button.

The following table lists all the buttons:

| Button | Description                                                      |
| ------ | ---------------------------------------------------------------- |
| 0      | Primary button, usually the left button.                         |
| 1      | Secondary button, usually the right button.                      |
| 2      | Auxiliary button, usually the wheel button or the middle button. |
| 3      | The fourth button, typically the back button.                    |
| 4      | The fifth button, typically the forward button.                  |
| 5-31   | Other buttons.                                                   |

`{ "action": { "run": "open -a Launchpad" }}` assigns a shell command `open -a LaunchPad` to
the button. When the button is clicked, the shell command will be executed.

## Open Mission Control when <kbd>command</kbd> + the forward button is clicked

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
            "action": {
              "run": "open -a 'Mission Control'"
            }
          }
        ]
      }
    }
  ]
}
```

In this example, `"command": true` denotes that <kbd>command</kbd> should be pressed.

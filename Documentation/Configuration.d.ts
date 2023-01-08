type SingleValueOrArray<T> = T | T[];

/** @asType number */
type Int = number;

/** @pattern ^\d+$ */
type IntString = string;

/** @pattern ^0x[0-9a-fA-F]+$ */
type HexString = string;

export type Configuration = {
  $schema?: string;

  /**
   * @title Schemes
   * @description A scheme is a collection of settings that are activated in specified circumstances.
   * @examples [{"if":{"device":{"category":"mouse"}},"scrolling":{"reverse":"vertical"}}]
   */
  schemes?: Scheme[];
};

type Scheme = {
  /**
   * @title Scheme activation conditions
   * @description This value can be a single condition or an array. A scheme is activated if at least one of the conditions is met.
   */
  if?: SingleValueOrArray<Scheme.If>;

  /**
   * @title Scrolling settings
   * @description Customize the scrolling behavior.
   */
  scrolling?: Scheme.Scrolling;

  /**
   * @title Pointer settings
   * @description Customize the pointer acceleration and speed.
   */
  pointer?: Scheme.Pointer;

  /**
   * @title Buttons settings
   * @description Customize the buttons behavior.
   */
  buttons?: Scheme.Buttons;
};

declare namespace Scheme {
  type If = {
    /**
     * @title Device
     * @description Match one or more devices. If not provided, the scheme is activated on all devices.
     */
    device?: If.Device;

    /**
     * @title App
     * @description Match apps by providing the bundle ID. For example, `com.apple.Safari`.
     */
    app?: string;

    /**
     * @title Parent app
     * @description Match apps by providing the bundle ID of the parent process. For example, `org.polymc.PolyMC`.
     */
    parentApp?: string;

    /**
     * @title Group app
     * @description Match apps by providing the bundle ID of the process group. For example, `org.polymc.PolyMC`.
     */
    groupApp?: string;
  };

  namespace If {
    type Device = {
      /**
       * @title Vendor ID
       * @description The vendor ID of the devices.
       * @examples ["0xA123"]
       */
      vendorID?: HexString | Int;

      /**
       * @title Product ID
       * @description The product ID of the devices.
       * @examples ["0xA123"]
       */
      productID?: HexString | Int;

      /**
       * @title Product name
       * @description The product name of the devices.
       */
      productName?: string;

      /**
       * @title Serial number
       * @description The serial number of the devices.
       */
      serialNumber?: string;

      /**
       * @title Category
       * @description The category of the devices.
       */
      category?: SingleValueOrArray<Category>;
    };

    /**
     * @title Mouse
     * @description Match mouse devices.
     */
    type Mouse = "mouse";

    /**
     * @title Trackpad
     * @description Match trackpad devices.
     */
    type Trackpad = "trackpad";

    type Category = Mouse | Trackpad;
  }

  type Scrolling = {
    /**
     * @title Reverse scrolling
     */
    reverse?: Scrolling.Reverse;

    /**
     * @title Scrolling distance
     * @description The distance after rolling the wheel.
     */
    distance?: Scrolling.Distance;

    /**
     * @title Modifier keys settings
     */
    modifiers?: Scrolling.Modifiers;
  };

  namespace Scrolling {
    type Bidirectional<T> =
      | T
      | {
          vertical: T;
          horizontal: T;
        };

    type Reverse = Bidirectional<boolean | undefined>;

    /**
     * @description The scrolling distance will not be modified.
     */
    type Auto = "auto";

    type Distance = Bidirectional<Auto | Distance.Line | Distance.Pixel>;

    namespace Distance {
      /**
       * @description The scrolling distance in lines.
       */
      type Line = Int | IntString;

      /**
       * @description The scrolling distance in pixels.
       * @pattern ^\d[1-9]*(\.\d+)?px
       */
      type Pixel = string;
    }

    type Modifiers = {
      /**
       * @description The action when command key is pressed.
       */
      command?: Modifiers.Action;

      /**
       * @description The action when shift key is pressed.
       */
      shift?: Modifiers.Action;

      /**
       * @description The action when option key is pressed.
       */
      option?: Modifiers.Action;

      /**
       * @description The action when control key is pressed.
       */
      control?: Modifiers.Action;
    };

    namespace Modifiers {
      /**
       * @description No actions.
       */
      type None = { type: "none" };

      /**
       * @description Alter the scrolling orientation from vertical to horizontal or vice versa.
       */
      type AlterOrientation = {
        type: "alterOrientation";
      };

      /**
       * @description Scale the scrolling speed.
       */
      type ChangeSpeed = {
        type: "changeSpeed";

        /**
         * @description The factor to scale the scrolling speed.
         */
        scale: number;
      };

      type Action = None | AlterOrientation | ChangeSpeed;
    }
  }

  type Pointer = {
    /**
     * @title Pointer acceleration
     * @description If the value is not specified, system default value will be used.
     * @minimum 0
     * @maximum 20
     */
    acceleration?: number;

    /**
     * @title Pointer speed
     * @description If the value is not specified, device default value will be used.
     * @minimal 0
     * @maximum 1
     */
    speed?: number;

    /**
     * @title Disable pointer acceleration
     * @description If the value is true, the pointer acceleration will be disabled and acceleration and speed will not take effect.
     * @default false
     */
    disableAcceleration?: boolean;
  };

  type Buttons = {
    /**
     * @title Button mappings
     * @description Assign actions to buttons.
     */
    mappings?: Buttons.Mapping[];

    /**
     * @title Universal back and forward
     * @description If the value is true, the back and forward side buttons will be enabled in Safari and some other apps that do not handle these side buttons correctly. If the value is "backOnly" or "forwardOnly", only universal back or universal forward will be enabled.
     * @default false
     */
    universalBackForward?: Buttons.UniversalBackForward;
  };

  namespace Buttons {
    type Mapping = {
      /**
       * @title Button number
       * @description The button number. See https://developer.apple.com/documentation/coregraphics/cgmousebutton
       */
      button: Mapping.Button;

      /**
       * @description Indicates if the command modifier key should be pressed.
       */
      command?: boolean;

      /**
       * @description Indicates if the shift modifier key should be pressed.
       */
      shift?: boolean;

      /**
       * @description Indicates if the option modifier key should be pressed.
       */
      option?: boolean;

      /**
       * @description Indicates if the control modifier key should be pressed.
       */
      control?: boolean;

      /**
       * @title Action
       */
      action?: Mapping.Action;

      /**
       * @description Indicates if key repeat is enabled. If the value is true, the action will be repeatedly executed when the button is hold according to the key repeat settings in System Settings.
       */
      repeat?: boolean;
    };

    namespace Mapping {
      type Action =
        | SimpleAction
        | Run
        | MouseWheelScrollUpWithDistance
        | MouseWheelScrollDownWithDistance
        | MouseWheelScrollLeftWithDistance
        | MouseWheelScrollRightWithDistance;

      type SimpleAction =
        | Auto
        | None
        | MissionControlSpaceLeft
        | MissionControlSpaceRight
        | MissionControl
        | AppExpose
        | Launchpad
        | ShowDesktop
        | DisplayBrightnessUp
        | DisplayBrightnessDown
        | MediaVolumeUp
        | MediaVolumeDown
        | MediaMute
        | MediaPlayPause
        | MediaNext
        | MediaPrevious
        | MediaFastForward
        | MediaRewind
        | KeyboardBrightnessUp
        | KeyboardBrightnessDown
        | MouseWheelScrollUp
        | MouseWheelScrollDown
        | MouseWheelScrollLeft
        | MouseWheelScrollRight;

      /**
       * @description Do not modify the button behavior.
       */
      type Auto = "auto";

      /**
       * @description Prevent the button events.
       */
      type None = "none";

      /**
       * @description Mission Control.
       */
      type MissionControl = "missionControl";

      /**
       * @description Mission Control: Move left a space.
       */
      type MissionControlSpaceLeft = "missionControl.spaceLeft";

      /**
       * @description Mission Control: Move right a space.
       */
      type MissionControlSpaceRight = "missionControl.spaceRight";

      /**
       * @description App Exposé.
       */
      type AppExpose = "appExpose";

      /**
       * @description Launchpad.
       */
      type Launchpad = "launchpad";

      /**
       * @description Show desktop.
       */
      type ShowDesktop = "showDesktop";

      /**
       * @description Display: Brightness up.
       */
      type DisplayBrightnessUp = "display.brightnessUp";

      /**
       * @description Display: Brightness down.
       */
      type DisplayBrightnessDown = "display.brightnessDown";

      /**
       * @description Media: Volume up.
       */
      type MediaVolumeUp = "media.volumeUp";

      /**
       * @description Media: Volume down.
       */
      type MediaVolumeDown = "media.volumeDown";

      /**
       * @description Media: Toggle mute.
       */
      type MediaMute = "media.mute";

      /**
       * @description Media: Play / pause.
       */
      type MediaPlayPause = "media.playPause";

      /**
       * @description Media: Next.
       */
      type MediaNext = "media.next";

      /**
       * @description Media: Previous.
       */
      type MediaPrevious = "media.previous";

      /**
       * @description Media: Fast forward.
       */
      type MediaFastForward = "media.fastForward";

      /**
       * @description Media: Rewind.
       */
      type MediaRewind = "media.rewind";

      /**
       * @description Keyboard: Brightness up.
       */
      type KeyboardBrightnessUp = "keyboard.brightnessUp";

      /**
       * @description Keyboard: Brightness down.
       */
      type KeyboardBrightnessDown = "keyboard.brightnessDown";

      /**
       * @description Mouse: Wheel: Scroll up.
       */
      type MouseWheelScrollUp = "mouse.wheel.scrollUp";

      /**
       * @description Mouse: Wheel: Scroll down.
       */
      type MouseWheelScrollDown = "mouse.wheel.scrollDown";

      /**
       * @description Mouse: Wheel: Scroll left.
       */
      type MouseWheelScrollLeft = "mouse.wheel.scrollLeft";

      /**
       * @description Mouse: Wheel: Scroll right.
       */
      type MouseWheelScrollRight = "mouse.wheel.scrollRight";

      type Run = {
        /**
         * @description Run a specific command. For example, `"open -a 'Mission Control'"`.
         */
        run: string;
      };

      type MouseWheelScrollUpWithDistance = {
        /**
         * @description Mouse: Wheel: Scroll up a certain distance.
         */
        "mouse.wheel.scrollUp": Scheme.Scrolling.Distance;
      };

      type MouseWheelScrollDownWithDistance = {
        /**
         * @description Mouse: Wheel: Scroll down a certain distance.
         */
        "mouse.wheel.scrollDown": Scheme.Scrolling.Distance;
      };

      type MouseWheelScrollLeftWithDistance = {
        /**
         * @description Mouse: Wheel: Scroll left a certain distance.
         */
        "mouse.wheel.scrollLeft": Scheme.Scrolling.Distance;
      };

      type MouseWheelScrollRightWithDistance = {
        /**
         * @description Mouse: Wheel: Scroll right a certain distance.
         */
        "mouse.wheel.scrollRight": Scheme.Scrolling.Distance;
      };

      type Button = Primary | Secondary | Auxiliary | Back | Forward | number;

      /**
       * @description Primary button, usually the left button.
       */
      type Primary = 0;

      /**
       * @description Secondary button, usually the right button.
       */
      type Secondary = 1;

      /**
       * @description Auxiliary button, usually the wheel button or the middle button.
       */
      type Auxiliary = 2;

      /**
       * @description Forth button, typically the back button.
       */
      type Back = 3;

      /**
       * @description Fifth button, typically the forward button.
       */
      type Forward = 4;
    }

    type UniversalBackForward =
      | boolean
      | UniversalBackForward.BackOnly
      | UniversalBackForward.ForwardOnly;

    namespace UniversalBackForward {
      /**
       * @description Enable universal back only.
       */
      type BackOnly = "backOnly";

      /**
       * @description Enable universal forward only.
       */
      type ForwardOnly = "forwardOnly";
    }
  }
}

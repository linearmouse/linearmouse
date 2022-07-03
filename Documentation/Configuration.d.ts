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
     * @description Match one or more devices.
     */
    device?: If.Device;
  };

  namespace If {
    type Device = {
      /**
       * @title Vendor ID
       * @description The vendor ID of the devices.
       */
      vendorID?: HexString | Int;

      /**
       * @title Product ID
       * @description The product ID of the devices.
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
    type Reverse = {
      /**
       * @title Reverse vertically
       * @default false
       */
      vertical?: boolean;

      /**
       * @title Reverse horizontally
       * @default false
       */
      horizontal?: boolean;
    };

    /**
     * @description The scrolling distance will not be modified.
     */
    type Auto = "auto";

    type Distance = Auto | Distance.Line | Distance.Pixel;

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
    universalBackForward?: boolean;
  };
}

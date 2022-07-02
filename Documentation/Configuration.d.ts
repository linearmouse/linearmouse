type SingleValueOrArray<T> = T | T[];

/** @asType number */
type Int = number;

/** @pattern ^\d+$ */
type IntString = string;

/** @pattern ^0x[0-9a-fA-F]+$ */
type HexString = string;

export type Configuration = {
  $schema?: string;
  schemes?: Scheme[];
};

type Scheme = {
  if?: SingleValueOrArray<Scheme.If>;
  scrolling?: Scheme.Scrolling;
  pointer?: Scheme.Pointer;
  buttons?: Scheme.Buttons;
};

declare namespace Scheme {
  type If = {
    device?: If.Device;
  };

  namespace If {
    type Device = {
      vendorID?: HexString | Int;
      productID?: HexString | Int;
      productName?: string;
      serialNumber?: string;
      category?: SingleValueOrArray<Category>;
    };

    type Category = "mouse" | "trackpad";
  }

  type Scrolling = {
    reverse?: Scrolling.Reverse;
    distance?: Scrolling.Distance;
    modifiers?: Scrolling.Modifiers;
  };

  namespace Scrolling {
    type Reverse = {
      vertical?: boolean;
      horizontal?: boolean;
    };

    type Distance = "auto" | Distance.Line | Distance.Pixel;

    namespace Distance {
      type Line = Int | IntString;

      /** @pattern ^\d[1-9]*(\.\d+)?px */
      type Pixel = string;
    }

    type Modifiers = {
      command?: Modifiers.Action;
      shift?: Modifiers.Action;
      option?: Modifiers.Action;
      control?: Modifiers.Action;
    };

    namespace Modifiers {
      type Action =
        | {
            type: "none";
          }
        | {
            type: "alterOrientation";
          }
        | {
            type: "changeSpeed";
            scale: number;
          };
    }
  }

  type Pointer = {
    /**
     * @minimum 0
     * @maximum 20
     */
    acceleration?: number;

    /**
     * @minimal 0
     * @maximum 1
     */
    speed?: number;

    disableAcceleration?: boolean;
  };

  type Buttons = {
    universalBackForward?: boolean;
  };
}

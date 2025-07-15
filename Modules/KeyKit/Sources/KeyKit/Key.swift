// MIT License
// Copyright (c) 2021-2025 LinearMouse

public enum Key: String, Codable {
    case enter
    case tab
    case space
    case delete
    case escape
    case command
    case shift
    case capsLock
    case option
    case control
    case commandRight
    case shiftRight
    case optionRight
    case controlRight
    case arrowLeft
    case arrowRight
    case arrowDown
    case arrowUp
    case home
    case pageUp
    case backspace
    case end
    case pageDown
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z
    // Extended Latin keyboards (used for multiple languages):
    case ê
    case é
    case î
    case ô
    case û
    case ó
    case ö
    case ä
    // German keyboards:
    case ü
    case ß
    // Spanish keyboards:
    case á
    case í
    case ú
    case ñ
    // French keyboards:
    case ç
    case à
    case è
    case ù
    // Norwegian/Danish keyboards:
    case ã
    case õ
    // Swedish/Finnish keyboards:
    case å
    // Polish keyboards:
    case ą
    case ć
    case ę
    case ł
    case ń
    case ś
    case ź
    case ż
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case equal = "="
    case minus = "-"
    case semicolon = ";"
    case quote = "'"
    case comma = ","
    case period = "."
    case slash = "/"
    case backslash = "\\"
    case backquote = "`"
    case backetLeft = "["
    case backetRight = "]"
    case numpadPlus
    case numpadMinus
    case numpadMultiply
    case numpadDivide
    case numpadEnter
    case numpadEquals
    case numpadDecimal
    case numpadClear
    case numpad0
    case numpad1
    case numpad2
    case numpad3
    case numpad4
    case numpad5
    case numpad6
    case numpad7
    case numpad8
    case numpad9
}

extension Key {
    private static let modifiersKeys: Set<Key> = [.command, .shift, .option, .control,
                                                  .commandRight, .shiftRight, .optionRight, .controlRight]

    public var isModifier: Bool {
        Self.modifiersKeys.contains(self)
    }
}

extension Key: CustomStringConvertible {
    public var description: String {
        switch self {
        case .enter:
            return "↩"
        case .command, .commandRight:
            return "⌘"
        case .shift, .shiftRight:
            return "⇧"
        case .option, .optionRight:
            return "⌥"
        case .control, .controlRight:
            return "⌃"
        case .numpadPlus:
            return "Numpad +"
        case .numpadMinus:
            return "Numpad -"
        case .numpadMultiply:
            return "Numpad *"
        case .numpadDivide:
            return "Numpad /"
        case .numpadEnter:
            return "Numpad Enter"
        case .numpadEquals:
            return "Numpad ="
        case .numpadDecimal:
            return "Numpad ."
        case .numpadClear:
            return "Numpad Clear"
        case .numpad0:
            return "Numpad 0"
        case .numpad1:
            return "Numpad 1"
        case .numpad2:
            return "Numpad 2"
        case .numpad3:
            return "Numpad 3"
        case .numpad4:
            return "Numpad 4"
        case .numpad5:
            return "Numpad 5"
        case .numpad6:
            return "Numpad 6"
        case .numpad7:
            return "Numpad 7"
        case .numpad8:
            return "Numpad 8"
        case .numpad9:
            return "Numpad 9"
        default:
            return rawValue.prefix(1).capitalized + rawValue.dropFirst()
        }
    }
}

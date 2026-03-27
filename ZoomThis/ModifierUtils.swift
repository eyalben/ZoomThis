import SwiftUI

// Carbon modifier key constants (avoiding Carbon import for sandbox compatibility)
private let carbonControlKey: UInt32 = 0x1000
private let carbonOptionKey: UInt32 = 0x0800
private let carbonShiftKey: UInt32 = 0x0200
private let carbonCmdKey: UInt32 = 0x0100

func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
    carbonModifiersToString(modifiers) + keyCodeToString(keyCode)
}

func carbonModifiersToString(_ modifiers: UInt32) -> String {
    var result = ""
    if modifiers & carbonControlKey != 0 { result += "\u{2303}" }
    if modifiers & carbonOptionKey != 0 { result += "\u{2325}" }
    if modifiers & carbonShiftKey != 0 { result += "\u{21E7}" }
    if modifiers & carbonCmdKey != 0 { result += "\u{2318}" }
    return result
}

func cocoaToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.control) { carbon |= carbonControlKey }
    if flags.contains(.option) { carbon |= carbonOptionKey }
    if flags.contains(.shift) { carbon |= carbonShiftKey }
    if flags.contains(.command) { carbon |= carbonCmdKey }
    return carbon
}

func keyCodeToString(_ keyCode: UInt32) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 36: return "\u{21A9}"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 48: return "\u{21E5}"
    case 49: return "Space"
    case 50: return "`"
    case 51: return "\u{232B}"
    case 53: return "\u{238B}"
    default: return "Key\(keyCode)"
    }
}

func keyCodeToKeyEquivalent(_ keyCode: UInt32) -> KeyEquivalent? {
    switch keyCode {
    case 0: return KeyEquivalent("a")
    case 1: return KeyEquivalent("s")
    case 2: return KeyEquivalent("d")
    case 3: return KeyEquivalent("f")
    case 4: return KeyEquivalent("h")
    case 5: return KeyEquivalent("g")
    case 6: return KeyEquivalent("z")
    case 7: return KeyEquivalent("x")
    case 8: return KeyEquivalent("c")
    case 9: return KeyEquivalent("v")
    case 11: return KeyEquivalent("b")
    case 12: return KeyEquivalent("q")
    case 13: return KeyEquivalent("w")
    case 14: return KeyEquivalent("e")
    case 15: return KeyEquivalent("r")
    case 16: return KeyEquivalent("y")
    case 17: return KeyEquivalent("t")
    case 18: return KeyEquivalent("1")
    case 19: return KeyEquivalent("2")
    case 20: return KeyEquivalent("3")
    case 21: return KeyEquivalent("4")
    case 22: return KeyEquivalent("6")
    case 23: return KeyEquivalent("5")
    case 24: return KeyEquivalent("=")
    case 25: return KeyEquivalent("9")
    case 26: return KeyEquivalent("7")
    case 27: return KeyEquivalent("-")
    case 28: return KeyEquivalent("8")
    case 29: return KeyEquivalent("0")
    case 30: return KeyEquivalent("]")
    case 31: return KeyEquivalent("o")
    case 32: return KeyEquivalent("u")
    case 33: return KeyEquivalent("[")
    case 34: return KeyEquivalent("i")
    case 35: return KeyEquivalent("p")
    case 36: return .return
    case 37: return KeyEquivalent("l")
    case 38: return KeyEquivalent("j")
    case 39: return KeyEquivalent("'")
    case 40: return KeyEquivalent("k")
    case 41: return KeyEquivalent(";")
    case 42: return KeyEquivalent("\\")
    case 43: return KeyEquivalent(",")
    case 44: return KeyEquivalent("/")
    case 45: return KeyEquivalent("n")
    case 46: return KeyEquivalent("m")
    case 47: return KeyEquivalent(".")
    case 48: return .tab
    case 49: return .space
    case 50: return KeyEquivalent("`")
    case 51: return .delete
    case 53: return .escape
    default: return nil
    }
}

func carbonModifiersToEventModifiers(_ modifiers: UInt32) -> EventModifiers {
    var result: EventModifiers = []
    if modifiers & 0x1000 != 0 { result.insert(.control) }
    if modifiers & 0x0800 != 0 { result.insert(.option) }
    if modifiers & 0x0200 != 0 { result.insert(.shift) }
    if modifiers & 0x0100 != 0 { result.insert(.command) }
    return result
}

extension View {
    @ViewBuilder
    func hotkeyShortcut(keyCode: UInt32, modifiers: UInt32) -> some View {
        if let key = keyCodeToKeyEquivalent(keyCode) {
            self.keyboardShortcut(key, modifiers: carbonModifiersToEventModifiers(modifiers))
        } else {
            self
        }
    }
}

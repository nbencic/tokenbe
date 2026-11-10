/// A global shortcut as stored in `tb.ui.shortcut` (09): `modifier(+modifier)*+key`, modifiers `ctrl alt shift cmd`
/// (each once), key `a–z 0–9 f1–f12 space`; the empty string means none.
///
/// Converts between the stored text, macOS virtual key codes plus Carbon modifier masks (what
/// `RegisterEventHotKey` takes) and the symbols shown in Settings (`⌃⌥T`). Pure, so it is tested in Core.
public struct Shortcut: Equatable, Hashable, Sendable {
  public enum Modifier: String, CaseIterable, Sendable {
    // Declaration order is the display order macOS uses: ⌃ ⌥ ⇧ ⌘.
    case ctrl, alt, shift, cmd

    public var symbol: String {
      switch self {
      case .ctrl: "\u{2303}"
      case .alt: "\u{2325}"
      case .shift: "\u{21E7}"
      case .cmd: "\u{2318}"
      }
    }

    /// Carbon `controlKey`, `optionKey`, `shiftKey`, `cmdKey` (Events.h).
    public var carbonMask: UInt32 {
      switch self {
      case .ctrl: 1 << 12
      case .alt: 1 << 11
      case .shift: 1 << 9
      case .cmd: 1 << 8
      }
    }
  }

  public let modifiers: Set<Modifier>
  /// The key's stored name: `a`–`z`, `0`–`9`, `f1`–`f12` or `space`.
  public let key: String

  /// The stored form of 09, modifiers in display order.
  public var setting: String {
    (Modifier.allCases.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "+")
  }

  /// `⌃⌥T`, `⌘F5`, `⌃Space`.
  public var display: String {
    let name: String
    if key == "space" {
      name = "Space"
    } else {
      name = key.uppercased()
    }
    return Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined() + name
  }

  public var carbonModifiers: UInt32 {
    modifiers.reduce(0) { $0 | $1.carbonMask }
  }

  /// The macOS virtual key code (`kVK_*`) of `key`. Every valid key has one.
  public var keyCode: UInt32 {
    Self.keyCodes[key] ?? 0
  }

  /// Parses a stored value. Nil for the empty string (no shortcut) and for anything 09's pattern rejects.
  public init?(setting: String) {
    guard !setting.isEmpty, SettingSpec.matches(setting, .shortcut) else { return nil }
    let parts = setting.split(separator: "+").map(String.init)
    guard let key = parts.last else { return nil }
    self.modifiers = Set(parts.dropLast().compactMap(Modifier.init(rawValue:)))
    self.key = key
  }

  /// A key press seen by the recorder. Nil when the key has no stored name or no modifier is held: 09 requires
  /// at least one modifier, and a bare key would fire while typing.
  public init?(keyCode: UInt16, modifiers: Set<Modifier>) {
    guard !modifiers.isEmpty, let key = Self.names[UInt32(keyCode)] else { return nil }
    self.modifiers = modifiers
    self.key = key
  }

  /// `kVK_ANSI_*`, `kVK_Space` and `kVK_F1`…`kVK_F12` from Carbon's Events.h.
  static let keyCodes: [String: UInt32] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
    "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
    "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22,
    "p": 0x23, "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E, "space": 0x31,
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64, "f9": 0x65,
    "f10": 0x6D, "f11": 0x67, "f12": 0x6F
  ]

  static let names: [UInt32: String] = Dictionary(uniqueKeysWithValues: keyCodes.map { ($1, $0) })

  /// `kVK_Escape` cancels recording; `kVK_Delete` (⌫) and `kVK_ForwardDelete` clear the shortcut.
  public static let escapeKeyCode: UInt16 = 0x35
  public static let deleteKeyCodes: Set<UInt16> = [0x33, 0x75]
}

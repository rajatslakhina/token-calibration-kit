/// The classes a tokenizer-free estimate counts text by.
///
/// BPE vocabularies spend tokens very differently on each one. An English letter costs about a fifth
/// of a token, a CJK character about one, a composed emoji several. A single characters-per-token
/// ratio averages these away, which is why `count / 4` under-counts CJK text, code and emoji.
public enum ScalarClass: Int, CaseIterable, Sendable, Hashable {
    /// `A`-`Z` and `a`-`z`.
    case asciiLetter
    /// ASCII digits and any other scalar with a numeric value outside the CJK blocks.
    case digit
    /// Spaces, tabs and newlines, including non-ASCII spaces.
    case whitespace
    /// Printable ASCII that is not a letter or a digit: brackets, quotes, operators.
    case asciiPunctuation
    /// Han, Hiragana, Katakana, Hangul, CJK punctuation and fullwidth forms.
    case cjk
    /// Alphabetic scalars outside ASCII and CJK: accented Latin, Cyrillic, Greek, Arabic, Devanagari.
    case otherLetter
    /// A whole emoji grapheme (a flag, a ZWJ family, a symbol with an emoji presentation selector),
    /// counted once however many scalars it has.
    case emoji
    /// Everything else: symbols, combining marks, control characters.
    case other

    /// A short name for reports.
    public var label: String {
        switch self {
        case .asciiLetter: "ascii letter"
        case .digit: "digit"
        case .whitespace: "whitespace"
        case .asciiPunctuation: "ascii punctuation"
        case .cjk: "cjk"
        case .otherLetter: "other letter"
        case .emoji: "emoji"
        case .other: "other"
        }
    }

    /// The class of one scalar that is not part of an emoji grapheme.
    static func classify(_ scalar: Unicode.Scalar) -> ScalarClass {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A:
            return .asciiLetter
        case 0x30...0x39:
            return .digit
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
            return .asciiPunctuation
        default:
            break
        }
        let properties = scalar.properties
        if properties.isWhitespace {
            return .whitespace
        }
        if cjkRanges.contains(where: { $0.contains(scalar.value) }) {
            return .cjk
        }
        if properties.numericType != nil {
            return .digit
        }
        return properties.isAlphabetic ? .otherLetter : .other
    }

    /// Whether a grapheme is drawn as an emoji: any scalar with an emoji presentation, or the
    /// emoji presentation selector U+FE0F.
    static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
    }

    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11FF, // Hangul Jamo
        0x3000...0x303F, // CJK symbols and punctuation
        0x3040...0x309F, // Hiragana
        0x30A0...0x30FF, // Katakana
        0x3130...0x318F, // Hangul compatibility Jamo
        0x3400...0x4DBF, // CJK unified ideographs extension A
        0x4E00...0x9FFF, // CJK unified ideographs
        0xAC00...0xD7AF, // Hangul syllables
        0xF900...0xFAFF, // CJK compatibility ideographs
        0xFF00...0xFFEF, // Halfwidth and fullwidth forms
        0x20000...0x2FA1F // CJK extensions B to F and the compatibility supplement
    ]
}

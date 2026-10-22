/// What a tokenizer-free estimate knows about some text: how many scalars of each class it has,
/// plus the framing a chat request adds around it.
///
/// Features add, so a prompt's features are the sum of its messages' features plus one request.
/// Completion text has no framing: build it with `init(text:)` and the framing counts stay zero.
public struct TextFeatures: Hashable, Sendable {
    /// Scalar counts indexed by `ScalarClass.rawValue`. Emoji are counted per grapheme.
    private var counts: [Int]
    /// Chat messages in the request. Each one costs role markers and separators.
    public private(set) var messages: Int
    /// Tool definitions in the request. Each one is wrapped in framing of its own.
    public private(set) var tools: Int
    /// Requests: 1 for a prompt, 0 for completion text. Covers the fixed per-request overhead.
    public private(set) var requests: Int

    /// No text and no framing.
    public static let empty = TextFeatures(counts: Array(repeating: 0, count: ScalarClass.allCases.count))

    /// The features of a piece of text, with no framing.
    public init(text: String) {
        var counts = Array(repeating: 0, count: ScalarClass.allCases.count)
        for character in text {
            if ScalarClass.isEmoji(character) {
                counts[ScalarClass.emoji.rawValue] += 1
                continue
            }
            for scalar in character.unicodeScalars {
                counts[ScalarClass.classify(scalar).rawValue] += 1
            }
        }
        self.init(counts: counts)
    }

    private init(counts: [Int], messages: Int = 0, tools: Int = 0, requests: Int = 0) {
        self.counts = counts
        self.messages = messages
        self.tools = tools
        self.requests = requests
    }

    /// The features of one chat request: every message's text, every tool schema's text, one
    /// message frame per message, one tool frame per schema and one request.
    public static func prompt(messages: [String], toolSchemas: [String] = []) -> TextFeatures {
        var total = (messages + toolSchemas).reduce(TextFeatures.empty) { $0 + TextFeatures(text: $1) }
        total.messages = messages.count
        total.tools = toolSchemas.count
        total.requests = 1
        return total
    }

    /// How many scalars (graphemes for `.emoji`) of one class the text has.
    public func count(of scalarClass: ScalarClass) -> Int {
        counts[scalarClass.rawValue]
    }

    /// Every scalar and emoji grapheme counted, framing excluded. Roughly `String.unicodeScalars.count`.
    public var textUnits: Int {
        counts.reduce(0, +)
    }

    public static func + (lhs: TextFeatures, rhs: TextFeatures) -> TextFeatures {
        TextFeatures(
            counts: zip(lhs.counts, rhs.counts).map { $0 + $1 },
            messages: lhs.messages + rhs.messages,
            tools: lhs.tools + rhs.tools,
            requests: lhs.requests + rhs.requests
        )
    }

    /// The number of features: one per scalar class, then messages, tools and requests.
    static let dimension = ScalarClass.allCases.count + 3

    /// The features as a regression vector, in `dimension` order.
    var vector: [Double] {
        counts.map(Double.init) + [Double(messages), Double(tools), Double(requests)]
    }
}

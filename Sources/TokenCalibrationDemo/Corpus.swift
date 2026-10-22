/// A small deterministic generator, so the demo prints the same numbers on every run.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[next(items.count)]
    }
}

/// The chat traffic the demo bills: support questions, code, Japanese and emoji-heavy messages.
enum Corpus {
    static let system = "You are a careful assistant for an iOS team. Answer briefly and cite the docs you used."

    private static let words = [
        "the", "app", "crashes", "when", "a", "background", "upload", "resumes", "after", "suspension",
        "configuration", "identifier", "session", "delegate", "callback", "should", "we", "retry",
        "notification", "permission", "keychain", "migration", "concurrency", "actor", "isolation",
        "warning", "release", "build", "simulator", "device", "memory", "graph", "leak", "view", "model"
    ]
    private static let japanese = [
        "アップロードが中断されました", "設定を確認してください", "東京の天気", "予算の上限", "ありがとうございます",
        "バックグラウンドで再開する方法", "エラーが発生しました", "文脈の長さ"
    ]
    private static let emoji = ["👍", "🎉", "🚀", "❤️", "👨‍👩‍👧", "🇯🇵", "✅", "🔥"]
    private static let tools = [
        #"{"name":"search_docs","description":"Search the developer docs","parameters":"#
            + #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}}"#,
        #"{"name":"open_ticket","description":"Open a support ticket","parameters":{"type":"object","#
            + #""properties":{"title":{"type":"string"},"priority":{"type":"integer","minimum":1,"maximum":4}}}}"#
    ]

    static func request(_ kind: ChatRequest.Kind, using rng: inout SeededGenerator) -> ChatRequest {
        var messages = [system]
        for _ in 0..<(1 + rng.next(3)) {
            messages.append(message(kind, using: &rng))
        }
        let toolCount = rng.next(3)
        return ChatRequest(kind: kind, messages: messages, tools: Array(tools.prefix(toolCount)))
    }

    static func message(_ kind: ChatRequest.Kind, using rng: inout SeededGenerator) -> String {
        switch kind {
        case .english:
            return sentence(length: 12 + rng.next(70), using: &rng)
        case .code:
            return code(lines: 3 + rng.next(12), using: &rng)
        case .japanese:
            return (0..<(4 + rng.next(24))).map { _ in rng.pick(japanese) }.joined(separator: "。")
        case .emoji:
            let words = (0..<(8 + rng.next(30))).map { index in
                index % 3 == 0 ? rng.pick(emoji) : rng.pick(Self.words)
            }
            return words.joined(separator: " ")
        }
    }

    static func sentence(length: Int, using rng: inout SeededGenerator) -> String {
        (0..<length).map { _ in rng.pick(words) }.joined(separator: " ") + "."
    }

    static func code(lines: Int, using rng: inout SeededGenerator) -> String {
        (0..<lines).map { index in
            let name = rng.pick(words)
            let call = "client.\(name)(id: \(rng.next(90_000)), retries: \(rng.next(9)))"
            return "    let \(name)\(index) = try await " + call
        }.joined(separator: "\n")
    }
}

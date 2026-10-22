@testable import TokenCalibrationKit
import XCTest

final class FeatureTests: XCTestCase {
    func testEachScalarClass() {
        let cases: [(String, ScalarClass)] = [
            ("A", .asciiLetter), ("z", .asciiLetter), ("7", .digit), ("\u{0663}", .digit),
            (" ", .whitespace), ("\n", .whitespace), ("\u{3000}", .whitespace), ("{", .asciiPunctuation),
            ("~", .asciiPunctuation), ("日", .cjk), ("か", .cjk), ("カ", .cjk), ("한", .cjk), ("\u{FF21}", .cjk),
            ("é", .otherLetter), ("Ж", .otherLetter), ("©", .other), ("\u{0301}", .other)
        ]
        for (text, expected) in cases {
            let features = TextFeatures(text: text)
            XCTAssertEqual(features.count(of: expected), text.unicodeScalars.count, "\(text)")
            XCTAssertEqual(features.textUnits, text.unicodeScalars.count, "\(text)")
        }
    }

    func testEmojiAreCountedOncePerGrapheme() {
        let features = TextFeatures(text: "👍❤️👨‍👩‍👧🇯🇵")
        XCTAssertEqual(features.count(of: .emoji), 4)
        XCTAssertEqual(features.textUnits, 4)
        XCTAssertEqual(TextFeatures(text: "©").count(of: .emoji), 0)
    }

    func testLabelsAreDistinct() {
        let labels = ScalarClass.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, ScalarClass.allCases.count)
        XCTAssertEqual(ScalarClass.cjk.label, "cjk")
    }

    func testPromptAddsFraming() {
        let prompt = TextFeatures.prompt(messages: ["Hi there", "ok"], toolSchemas: ["{\"a\":1}"])
        XCTAssertEqual(prompt.messages, 2)
        XCTAssertEqual(prompt.tools, 1)
        XCTAssertEqual(prompt.requests, 1)
        XCTAssertEqual(prompt.count(of: .asciiLetter), 10)
        XCTAssertEqual(prompt.count(of: .asciiPunctuation), 5)
        XCTAssertEqual(prompt.count(of: .digit), 1)
        XCTAssertEqual(prompt.count(of: .whitespace), 1)
        XCTAssertEqual(prompt.vector.count, TextFeatures.dimension)
        XCTAssertEqual(Array(prompt.vector.suffix(3)), [2, 1, 1])
    }

    func testFeaturesAdd() {
        let sum = TextFeatures(text: "ab") + TextFeatures.prompt(messages: ["c"])
        XCTAssertEqual(sum.count(of: .asciiLetter), 3)
        XCTAssertEqual(sum.messages, 1)
        XCTAssertEqual(sum.requests, 1)
        XCTAssertEqual(TextFeatures.empty.textUnits, 0)
        XCTAssertEqual(TextFeatures(text: ""), .empty)
    }
}

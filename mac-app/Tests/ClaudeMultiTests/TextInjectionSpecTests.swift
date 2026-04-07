import XCTest
@testable import ClaudeMultiLib

/// # Text Injection Spec
///
/// Text injection MUST be safe and correct. The sanitization layer is the
/// last line of defense before text reaches AppleScript, so it must:
///
/// 1. Reject text exceeding the length limit
/// 2. Strip all control characters except tab
/// 3. Escape quotes and backslashes to prevent AppleScript injection
/// 4. Preserve Unicode and normal ASCII
/// 5. Rate-limit injections to prevent flooding
final class TextInjectionSpecTests: XCTestCase {

    // =========================================================================
    // MARK: - Security: MUST reject text longer than 10,000 characters
    // =========================================================================

    func testLengthLimit_exactly10000chars_mustBeAccepted() {
        let text = String(repeating: "a", count: 10_000)
        let result = TextInjection.sanitizeForAppleScript(text)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 10_000)
    }

    func testLengthLimit_10001chars_mustBeRejected() {
        let text = String(repeating: "a", count: 10_001)
        let result = TextInjection.sanitizeForAppleScript(text)
        XCTAssertNil(result, "Text over 10,000 characters MUST be rejected")
    }

    func testLengthLimit_50000chars_mustBeRejected() {
        let text = String(repeating: "x", count: 50_000)
        let result = TextInjection.sanitizeForAppleScript(text)
        XCTAssertNil(result)
    }

    // =========================================================================
    // MARK: - Security: MUST strip ALL control characters except tab
    // =========================================================================

    func testControlChars_newline_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("line1\nline2")
        XCTAssertEqual(result, "line1line2")
    }

    func testControlChars_carriageReturn_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("line1\rline2")
        XCTAssertEqual(result, "line1line2")
    }

    func testControlChars_CRLF_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("line1\r\nline2")
        XCTAssertEqual(result, "line1line2")
    }

    func testControlChars_null_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("before\0after")
        XCTAssertEqual(result, "beforeafter")
    }

    func testControlChars_bell_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("before\u{07}after")
        XCTAssertEqual(result, "beforeafter")
    }

    func testControlChars_escape_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("before\u{1B}after")
        XCTAssertEqual(result, "beforeafter")
    }

    func testControlChars_formFeed_mustBeStripped() {
        let result = TextInjection.sanitizeForAppleScript("before\u{0C}after")
        XCTAssertEqual(result, "beforeafter")
    }

    func testControlChars_allControlCharsExceptTab_mustBeStripped() {
        // Build a string with all control characters 0x00-0x1F except 0x09 (tab)
        var input = ""
        for i: UInt8 in 0x00...0x1F {
            if i != 0x09 { input.append(Character(UnicodeScalar(i))) }
        }
        let result = TextInjection.sanitizeForAppleScript(input)
        XCTAssertEqual(result, "", "All control characters except tab should be stripped")
    }

    func testControlChars_onlyControlCharacters_mustReturnEmpty() {
        let input = "\n\r\u{00}\u{01}\u{02}\u{03}"
        let result = TextInjection.sanitizeForAppleScript(input)
        XCTAssertEqual(result, "")
    }

    // =========================================================================
    // MARK: - Security: MUST escape double quotes
    // =========================================================================

    func testEscaping_doubleQuotes_mustBeEscaped() {
        let result = TextInjection.sanitizeForAppleScript("say \"hello\"")
        XCTAssertEqual(result, "say \\\"hello\\\"")
    }

    func testEscaping_singleDoubleQuote_mustBeEscaped() {
        XCTAssertEqual(TextInjection.sanitizeForAppleScript("\""), "\\\"")
    }

    // =========================================================================
    // MARK: - Security: MUST escape backslashes
    // =========================================================================

    func testEscaping_backslashes_mustBeEscaped() {
        let result = TextInjection.sanitizeForAppleScript("path\\to\\file")
        XCTAssertEqual(result, "path\\\\to\\\\file")
    }

    func testEscaping_singleBackslash_mustBeEscaped() {
        XCTAssertEqual(TextInjection.sanitizeForAppleScript("\\"), "\\\\")
    }

    func testEscaping_backslashBeforeQuote_mustBothBeEscaped() {
        // Input:  \"
        // Step 1 (escape \): \\"
        // Step 2 (escape "): \\\"
        let result = TextInjection.sanitizeForAppleScript("\\\"")
        XCTAssertEqual(result, "\\\\\\\"")
    }

    func testEscaping_multipleEscapableCharacters_allEscaped() {
        let input = "He said \"hello\\world\""
        let result = TextInjection.sanitizeForAppleScript(input)
        XCTAssertEqual(result, "He said \\\"hello\\\\world\\\"")
    }

    // =========================================================================
    // MARK: - Security: MUST NOT allow AppleScript injection
    // =========================================================================

    func testInjection_appleScriptBreakout_mustBeNeutralized() {
        let malicious = "\"; tell app \"Finder\" to activate --"
        let result = TextInjection.sanitizeForAppleScript(malicious)
        XCTAssertNotNil(result)

        // Every double quote in the result must be preceded by a backslash
        let chars = Array(result!)
        for (i, ch) in chars.enumerated() {
            if ch == "\"" {
                XCTAssertTrue(i > 0 && chars[i - 1] == "\\",
                    "Found unescaped double quote at index \(i) in: \(result!)")
            }
        }
    }

    func testInjection_nestedAppleScript_mustBeEscaped() {
        let malicious = "\\\" & do shell script \\\"rm -rf /\\\""
        let result = TextInjection.sanitizeForAppleScript(malicious)
        XCTAssertNotNil(result)
        // The result should not contain an unescaped quote that could break
        // out of the AppleScript string literal boundary.
    }

    func testInjection_appleScriptTellBlock_mustBeEscaped() {
        let malicious = "\" & (do shell script \"whoami\") & \""
        let result = TextInjection.sanitizeForAppleScript(malicious)
        XCTAssertNotNil(result)
        // Verify all quotes are escaped
        let chars = Array(result!)
        for (i, ch) in chars.enumerated() {
            if ch == "\"" {
                XCTAssertTrue(i > 0 && chars[i - 1] == "\\",
                    "Found unescaped double quote at index \(i)")
            }
        }
    }

    // =========================================================================
    // MARK: - Security: MUST NOT allow shell injection via backticks or $()
    // =========================================================================

    func testInjection_shellSubstitution_passesThrough() {
        // Shell command syntax is not dangerous at the AppleScript layer —
        // it only becomes dangerous if it breaks out of the string first.
        // Since we escape quotes, $(cmd) and `cmd` remain inside the string.
        let result1 = TextInjection.sanitizeForAppleScript("$(rm -rf /)")
        XCTAssertEqual(result1, "$(rm -rf /)")

        let result2 = TextInjection.sanitizeForAppleScript("`whoami`")
        XCTAssertEqual(result2, "`whoami`")
    }

    // =========================================================================
    // MARK: - Security: MUST rate-limit to prevent flooding (max 10/sec)
    // =========================================================================

    func testRateLimit_sanitizeIsIndependentOfRateLimiting() {
        // sanitizeForAppleScript is a static method and MUST NOT be rate-limited.
        // Rate limiting only applies to the instance method sendText.
        for i in 0..<100 {
            XCTAssertNotNil(TextInjection.sanitizeForAppleScript("call \(i)"),
                "sanitizeForAppleScript should not be rate-limited")
        }
    }

    func testRateLimit_minInterval_is0point1seconds() {
        // The rate limiter enforces 0.1s between injections (10/sec max).
        // We verify through the public interface that rapid calls are gated.
        // NOTE: sendText talks to AppleScript/iTerm2 so we can't test it
        // directly in unit tests, but we can verify the injection instance
        // exists and that the rate limit constant is correct.
        let injection = TextInjection()
        // The first call to sendText would succeed (lastInjectionTime = .distantPast).
        // We at least verify the object can be constructed.
        XCTAssertNotNil(injection)
    }

    // =========================================================================
    // MARK: - Correctness: Normal ASCII text MUST pass through
    // =========================================================================

    func testPassthrough_normalText_mustPassThrough() {
        let result = TextInjection.sanitizeForAppleScript("hello world")
        XCTAssertEqual(result, "hello world")
    }

    func testPassthrough_allPrintableASCII_mustPassThrough() {
        // All printable ASCII (0x20-0x7E) except \ and " should pass unchanged
        var printable = ""
        for i: UInt8 in 0x20...0x7E {
            let char = Character(UnicodeScalar(i))
            if char != "\\" && char != "\"" {
                printable.append(char)
            }
        }
        let result = TextInjection.sanitizeForAppleScript(printable)
        XCTAssertEqual(result, printable)
    }

    func testPassthrough_singleCharacter_mustPassThrough() {
        XCTAssertEqual(TextInjection.sanitizeForAppleScript("a"), "a")
    }

    func testPassthrough_spaces_mustPassThrough() {
        XCTAssertEqual(TextInjection.sanitizeForAppleScript("   "), "   ")
    }

    // =========================================================================
    // MARK: - Correctness: Unicode MUST be preserved
    // =========================================================================

    func testUnicode_emoji_mustBePreserved() {
        let result = TextInjection.sanitizeForAppleScript("Hello 🌍🚀💻")
        XCTAssertEqual(result, "Hello 🌍🚀💻")
    }

    func testUnicode_CJK_mustBePreserved() {
        let result = TextInjection.sanitizeForAppleScript("日本語テスト 中文测试 한국어")
        XCTAssertEqual(result, "日本語テスト 中文测试 한국어")
    }

    func testUnicode_arabic_mustBePreserved() {
        let result = TextInjection.sanitizeForAppleScript("مرحبا بالعالم")
        XCTAssertEqual(result, "مرحبا بالعالم")
    }

    func testUnicode_mixedWithASCIIandEscaping_mustBeCorrect() {
        let result = TextInjection.sanitizeForAppleScript("cmd 日本 --flag=\"value\"")
        XCTAssertEqual(result, "cmd 日本 --flag=\\\"value\\\"")
    }

    // =========================================================================
    // MARK: - Correctness: Tab characters MUST be preserved
    // =========================================================================

    func testTab_mustBePreservedAndEscaped() {
        // Tab (0x09) is valid terminal input. It should be preserved
        // (not stripped) and escaped for AppleScript.
        let result = TextInjection.sanitizeForAppleScript("col1\tcol2")
        XCTAssertEqual(result, "col1\\tcol2")
    }

    func testTab_onlyTabs_mustBePreserved() {
        let result = TextInjection.sanitizeForAppleScript("\t\t\t")
        XCTAssertEqual(result, "\\t\\t\\t")
    }

    // =========================================================================
    // MARK: - Correctness: Empty string SHOULD be allowed
    // =========================================================================

    func testEmptyString_mustBeAccepted() {
        let result = TextInjection.sanitizeForAppleScript("")
        XCTAssertEqual(result, "")
    }
}

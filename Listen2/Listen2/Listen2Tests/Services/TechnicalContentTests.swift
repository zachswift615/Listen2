//
//  TechnicalContentTests.swift
//  Listen2Tests
//
//  Tests for premium word-level highlighting with technical content
//  Verifies alignment handles abbreviations, mathematical notation, code snippets
//

import XCTest
@testable import Listen2

/// Tests for technical content alignment (Task 10)
/// Ensures the premium alignment pipeline handles:
/// - Technical abbreviations (TCP/IP, HTTP/HTTPS, API, DNS)
/// - Mathematical notation (O(n²), x², √2)
/// - Code snippets (api.getData(), console.log())
/// - Mixed complex content
final class TechnicalContentTests: XCTestCase {

    // MARK: - Technical Abbreviation Tests

    func testHandlesTCPIPAbbreviation() {
        let mapper = TextNormalizationMapper()

        // TCP/IP gets spelled out character-by-character with slash
        let mapping = mapper.buildMapping(
            display: ["Using", "TCP/IP", "protocol"],
            synthesized: ["Using", "T", "C", "P", "slash", "I", "P", "protocol"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Using
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // TCP/IP
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4, 5, 6]) // T C P slash I P
        XCTAssertEqual(mapping[2].displayIndices, [2])      // protocol
        XCTAssertEqual(mapping[2].synthesizedIndices, [7])
    }

    func testHandlesHTTPHTTPSAbbreviation() {
        let mapper = TextNormalizationMapper()

        // HTTP/HTTPS gets spelled out character-by-character
        let mapping = mapper.buildMapping(
            display: ["Use", "HTTP/HTTPS", "only"],
            synthesized: ["Use", "H", "T", "T", "P", "slash", "H", "T", "T", "P", "S", "only"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Use
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // HTTP/HTTPS
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) // H T T P slash H T T P S
        XCTAssertEqual(mapping[2].displayIndices, [2])      // only
        XCTAssertEqual(mapping[2].synthesizedIndices, [11])
    }

    func testHandlesAPIAbbreviation() {
        let mapper = TextNormalizationMapper()

        // API might be spelled out or spoken as word
        let mapping = mapper.buildMapping(
            display: ["The", "API", "returns"],
            synthesized: ["The", "A", "P", "I", "returns"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // API
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3]) // A P I
    }

    func testHandlesDNSAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["DNS", "server"],
            synthesized: ["D", "N", "S", "server"]
        )

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // DNS
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1, 2]) // D N S
    }

    func testHandlesURLSlashNotation() {
        let mapper = TextNormalizationMapper()

        // URLs with slashes
        let mapping = mapper.buildMapping(
            display: ["Visit", "http://example.com", "now"],
            synthesized: ["Visit", "h", "t", "t", "p", "colon", "slash", "slash", "example", "dot", "com", "now"]
        )

        // The URL should map to all the spoken components
        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // http://example.com
        // Should capture most of the synthesized words (the exact count may vary)
        XCTAssertGreaterThan(mapping[1].synthesizedIndices.count, 5)
    }

    // MARK: - Mathematical Notation Tests

    func testHandlesBigONotation() {
        let mapper = TextNormalizationMapper()

        // O(n²) gets spoken as "O n squared" or similar
        let mapping = mapper.buildMapping(
            display: ["Algorithm", "runs", "in", "O(n²)", "time"],
            synthesized: ["Algorithm", "runs", "in", "O", "n", "squared", "time"]
        )

        XCTAssertEqual(mapping.count, 5)
        XCTAssertEqual(mapping[3].displayIndices, [3])      // O(n²)
        XCTAssertEqual(mapping[3].synthesizedIndices, [3, 4, 5]) // O n squared
    }

    func testHandlesExponentNotation() {
        let mapper = TextNormalizationMapper()

        // x² might be spoken as "x squared"
        let mapping = mapper.buildMapping(
            display: ["The", "value", "x²", "equals"],
            synthesized: ["The", "value", "x", "squared", "equals"]
        )

        XCTAssertEqual(mapping.count, 4)
        XCTAssertEqual(mapping[2].displayIndices, [2])      // x²
        XCTAssertEqual(mapping[2].synthesizedIndices, [2, 3]) // x squared
    }

    func testHandlesSquareRoot() {
        let mapper = TextNormalizationMapper()

        // √2 might be spoken as "square root of two"
        let mapping = mapper.buildMapping(
            display: ["Calculate", "√2", "approximately"],
            synthesized: ["Calculate", "square", "root", "of", "two", "approximately"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // √2
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4]) // square root of two
    }

    func testHandlesFractionNotation() {
        let mapper = TextNormalizationMapper()

        // 1/2 might be spoken as "one half" or "one slash two"
        let mapping = mapper.buildMapping(
            display: ["Use", "1/2", "cup"],
            synthesized: ["Use", "one", "half", "cup"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // 1/2
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // one half
    }

    // MARK: - Code Snippet Tests

    func testHandlesMethodCall() {
        let mapper = TextNormalizationMapper()

        // api.getData() might be spoken as "api dot get data"
        let mapping = mapper.buildMapping(
            display: ["Call", "api.getData()", "method"],
            synthesized: ["Call", "a", "p", "i", "dot", "get", "data", "method"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // api.getData()
        // Should map to the spoken components
        XCTAssertGreaterThan(mapping[1].synthesizedIndices.count, 3)
    }

    func testHandlesVariableName() {
        let mapper = TextNormalizationMapper()

        // camelCase variables
        let mapping = mapper.buildMapping(
            display: ["Set", "userName", "value"],
            synthesized: ["Set", "user", "name", "value"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // userName
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // user name
    }

    func testHandlesConsoleLog() {
        let mapper = TextNormalizationMapper()

        // console.log() spoken
        let mapping = mapper.buildMapping(
            display: ["Use", "console.log()", "for"],
            synthesized: ["Use", "console", "dot", "log", "for"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // console.log()
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3]) // console dot log
    }

    func testHandlesObjectProperty() {
        let mapper = TextNormalizationMapper()

        // object.property notation
        let mapping = mapper.buildMapping(
            display: ["Access", "user.email", "field"],
            synthesized: ["Access", "user", "dot", "email", "field"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // user.email
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3]) // user dot email
    }

    // MARK: - Mixed Complex Content Tests

    func testHandlesMixedTechnicalContent() {
        let mapper = TextNormalizationMapper()

        // Complex sentence with multiple technical elements
        let mapping = mapper.buildMapping(
            display: ["The", "API", "uses", "HTTP/HTTPS", "for", "TCP/IP"],
            synthesized: ["The", "A", "P", "I", "uses", "H", "T", "T", "P", "slash", "H", "T", "T", "P", "S", "for", "T", "C", "P", "slash", "I", "P"]
        )

        XCTAssertEqual(mapping.count, 6)

        // API
        XCTAssertEqual(mapping[1].displayIndices, [1])
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3])

        // HTTP/HTTPS
        XCTAssertEqual(mapping[3].displayIndices, [3])
        XCTAssertEqual(mapping[3].synthesizedIndices, [5, 6, 7, 8, 9, 10, 11, 12, 13, 14])

        // TCP/IP
        XCTAssertEqual(mapping[5].displayIndices, [5])
        XCTAssertEqual(mapping[5].synthesizedIndices, [16, 17, 18, 19, 20, 21])
    }

    func testHandlesTechnicalTextWithContractions() {
        let mapper = TextNormalizationMapper()

        // Technical content mixed with contractions
        let mapping = mapper.buildMapping(
            display: ["I", "can't", "access", "TCP/IP"],
            synthesized: ["I", "can", "not", "access", "T", "C", "P", "slash", "I", "P"]
        )

        XCTAssertEqual(mapping.count, 4)

        // can't -> can not
        XCTAssertEqual(mapping[1].displayIndices, [1])
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2])

        // TCP/IP
        XCTAssertEqual(mapping[3].displayIndices, [3])
        XCTAssertEqual(mapping[3].synthesizedIndices, [4, 5, 6, 7, 8, 9])
    }

    func testHandlesMathWithNumbers() {
        let mapper = TextNormalizationMapper()

        // Math notation with numbers
        let mapping = mapper.buildMapping(
            display: ["The", "result", "is", "2²", "or", "4"],
            synthesized: ["The", "result", "is", "two", "squared", "or", "four"]
        )

        XCTAssertEqual(mapping.count, 6)

        // 2²
        XCTAssertEqual(mapping[3].displayIndices, [3])
        XCTAssertEqual(mapping[3].synthesizedIndices, [3, 4]) // two squared
    }

    func testHandlesCodeInSentence() {
        let mapper = TextNormalizationMapper()

        // Realistic code example in documentation
        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith's", "api.getData()", "method"],
            synthesized: ["Doctor", "Smith", "s", "a", "p", "i", "dot", "get", "data", "method"]
        )

        XCTAssertEqual(mapping.count, 4)

        // Dr.
        XCTAssertEqual(mapping[0].displayIndices, [0])
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])

        // Smith's
        XCTAssertEqual(mapping[1].displayIndices, [1])
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2])

        // api.getData()
        XCTAssertEqual(mapping[2].displayIndices, [2])
        XCTAssertEqual(mapping[2].synthesizedIndices, [3, 4, 5, 6, 7, 8])
    }

    // MARK: - Edge Cases

    func testHandlesMultipleSlashes() {
        let mapper = TextNormalizationMapper()

        // File paths with multiple slashes
        let mapping = mapper.buildMapping(
            display: ["Path", "/usr/bin/bash", "found"],
            synthesized: ["Path", "slash", "u", "s", "r", "slash", "b", "i", "n", "slash", "bash", "found"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // /usr/bin/bash
        // Should map to all the slash components
        XCTAssertGreaterThan(mapping[1].synthesizedIndices.count, 5)
    }

    func testHandlesParenthesesInCode() {
        let mapper = TextNormalizationMapper()

        // Function calls with parentheses
        let mapping = mapper.buildMapping(
            display: ["Call", "function()", "now"],
            synthesized: ["Call", "function", "now"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // function()
        XCTAssertEqual(mapping[1].synthesizedIndices, [1])   // function (parens stripped)
    }

    func testHandlesDollarSigns() {
        let mapper = TextNormalizationMapper()

        // LaTeX or currency
        let mapping = mapper.buildMapping(
            display: ["Price", "$50", "total"],
            synthesized: ["Price", "fifty", "dollars", "total"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // $50
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // fifty dollars
    }

    func testHandlesUnderscoresInIdentifiers() {
        let mapper = TextNormalizationMapper()

        // snake_case identifiers
        let mapping = mapper.buildMapping(
            display: ["Use", "max_value", "here"],
            synthesized: ["Use", "max", "value", "here"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // max_value
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // max value
    }

    // MARK: - Real-World Technical Examples

    func testHandlesNetworkingTerms() {
        let mapper = TextNormalizationMapper()

        // Realistic networking documentation
        let mapping = mapper.buildMapping(
            display: ["Configure", "TCP/IP", "and", "DNS", "settings"],
            synthesized: ["Configure", "T", "C", "P", "slash", "I", "P", "and", "D", "N", "S", "settings"]
        )

        XCTAssertEqual(mapping.count, 5)

        // TCP/IP
        XCTAssertEqual(mapping[1].displayIndices, [1])
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4, 5, 6])

        // DNS
        XCTAssertEqual(mapping[3].displayIndices, [3])
        XCTAssertEqual(mapping[3].synthesizedIndices, [8, 9, 10])
    }

    func testHandlesAlgorithmDescription() {
        let mapper = TextNormalizationMapper()

        // Algorithm analysis text
        let mapping = mapper.buildMapping(
            display: ["The", "algorithm", "runs", "in", "O(n²)", "time"],
            synthesized: ["The", "algorithm", "runs", "in", "O", "n", "squared", "time"]
        )

        XCTAssertEqual(mapping.count, 6)

        // O(n²)
        XCTAssertEqual(mapping[4].displayIndices, [4])
        XCTAssertEqual(mapping[4].synthesizedIndices, [4, 5, 6])
    }

    func testHandlesCodeDocumentation() {
        let mapper = TextNormalizationMapper()

        // Realistic code documentation
        let mapping = mapper.buildMapping(
            display: ["The", "user.getName()", "method", "returns"],
            synthesized: ["The", "user", "dot", "get", "name", "method", "returns"]
        )

        XCTAssertEqual(mapping.count, 4)

        // user.getName()
        XCTAssertEqual(mapping[1].displayIndices, [1])
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4])
    }

    // MARK: - Performance with Complex Content

    func testHandlesLongTechnicalSentence() {
        let mapper = TextNormalizationMapper()

        // Long sentence with multiple technical terms
        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith's", "research", "on", "TCP/IP", "couldn't", "use", "HTTP/HTTPS"],
            synthesized: ["Doctor", "Smith", "s", "research", "on", "T", "C", "P", "slash", "I", "P", "could", "not", "use", "H", "T", "T", "P", "slash", "H", "T", "T", "P", "S"]
        )

        XCTAssertEqual(mapping.count, 8)

        // Verify complex mapping preserved all words
        let displayIndices = mapping.map { $0.displayIndices[0] }
        XCTAssertEqual(displayIndices, [0, 1, 2, 3, 4, 5, 6, 7])

        // Verify technical terms mapped correctly
        // TCP/IP
        XCTAssertEqual(mapping[4].displayIndices, [4])
        XCTAssertEqual(mapping[4].synthesizedIndices, [5, 6, 7, 8, 9, 10])

        // couldn't
        XCTAssertEqual(mapping[5].displayIndices, [5])
        XCTAssertEqual(mapping[5].synthesizedIndices, [11, 12])

        // HTTP/HTTPS
        XCTAssertEqual(mapping[7].displayIndices, [7])
        XCTAssertEqual(mapping[7].synthesizedIndices, [14, 15, 16, 17, 18, 19, 20, 21, 22, 23])
    }
}

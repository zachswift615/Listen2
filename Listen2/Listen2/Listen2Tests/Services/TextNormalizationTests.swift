//
//  TextNormalizationTests.swift
//  Listen2Tests
//
//  Tests for mapping between display text and espeak-normalized synthesized text
//

import XCTest
@testable import Listen2

final class TextNormalizationTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func testMapsIdenticalWords() {
        let mapper = TextNormalizationMapper()

        // Test simple case where display == synthesized
        let mapping = mapper.buildMapping(
            display: ["Hello", "world"],
            synthesized: ["Hello", "world"]
        )

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[0].displayIndices, [0])
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])
        XCTAssertEqual(mapping[1].synthesizedIndices, [1])
    }

    func testMapsEmptyArrays() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: [],
            synthesized: []
        )

        XCTAssertEqual(mapping.count, 0)
    }

    // MARK: - Abbreviation Tests

    func testMapsDoctorAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith"],
            synthesized: ["Doctor", "Smith"]
        )

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Dr. -> Doctor
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // Smith -> Smith
        XCTAssertEqual(mapping[1].synthesizedIndices, [1])
    }

    func testMapsMisterAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Mr.", "Jones"],
            synthesized: ["Mister", "Jones"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // Mr. -> Mister
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
    }

    func testMapsMissusAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Mrs.", "Johnson"],
            synthesized: ["Missus", "Johnson"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // Mrs. -> Missus
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
    }

    func testMapsMissAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Ms.", "Williams"],
            synthesized: ["Miss", "Williams"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // Ms. -> Miss
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
    }

    func testMapsStreetAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Main", "St."],
            synthesized: ["Main", "Street"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // St. -> Street
        XCTAssertEqual(mapping[1].synthesizedIndices, [1])
    }

    func testMapsAvenueAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Park", "Ave."],
            synthesized: ["Park", "Avenue"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // Ave. -> Avenue
        XCTAssertEqual(mapping[1].synthesizedIndices, [1])
    }

    func testMapsMultipleAbbreviations() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith's", "office"],
            synthesized: ["Doctor", "Smith", "s", "office"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Dr. -> Doctor
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // Smith's -> Smith s
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2])
        XCTAssertEqual(mapping[2].displayIndices, [2])      // office -> office
        XCTAssertEqual(mapping[2].synthesizedIndices, [3])
    }

    // MARK: - Contraction Tests

    func testMapsCannotContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I", "can't", "go"],
            synthesized: ["I", "can", "not", "go"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[1].displayIndices, [1])      // can't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // can not
    }

    func testMapsWontContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["They", "won't", "come"],
            synthesized: ["They", "will", "not", "come"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // won't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // will not
    }

    func testMapsCouldntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["He", "couldn't", "go"],
            synthesized: ["He", "could", "not", "go"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // couldn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // could not
    }

    func testMapsShouldntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["You", "shouldn't", "stay"],
            synthesized: ["You", "should", "not", "stay"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // shouldn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // should not
    }

    func testMapsWouldntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["She", "wouldn't", "listen"],
            synthesized: ["She", "would", "not", "listen"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // wouldn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // would not
    }

    func testMapsDidntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I", "didn't", "see"],
            synthesized: ["I", "did", "not", "see"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // didn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // did not
    }

    func testMapsDoesntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["It", "doesn't", "matter"],
            synthesized: ["It", "does", "not", "matter"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // doesn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // does not
    }

    func testMapsDontContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I", "don't", "know"],
            synthesized: ["I", "do", "not", "know"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // don't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // do not
    }

    func testMapsIsntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["It", "isn't", "true"],
            synthesized: ["It", "is", "not", "true"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // isn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // is not
    }

    func testMapsArentContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["They", "aren't", "here"],
            synthesized: ["They", "are", "not", "here"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // aren't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // are not
    }

    func testMapsWasntContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["He", "wasn't", "ready"],
            synthesized: ["He", "was", "not", "ready"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // wasn't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // was not
    }

    func testMapsWerentContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["We", "weren't", "invited"],
            synthesized: ["We", "were", "not", "invited"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // weren't
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // were not
    }

    func testMapsIllContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I'll", "go"],
            synthesized: ["I", "will", "go"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // I'll
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // I will
    }

    func testMapsYoullContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["You'll", "see"],
            synthesized: ["You", "will", "see"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // You'll
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // You will
    }

    func testMapsHellContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["He'll", "come"],
            synthesized: ["He", "will", "come"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // He'll
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // He will
    }

    func testMapsShellContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["She'll", "arrive"],
            synthesized: ["She", "will", "arrive"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // She'll
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // She will
    }

    func testMapsWellContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["We'll", "try"],
            synthesized: ["We", "will", "try"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // We'll
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // We will
    }

    func testMapsTheyllContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["They'll", "help"],
            synthesized: ["They", "will", "help"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // They'll
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // They will
    }

    func testMapsIveContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I've", "been"],
            synthesized: ["I", "have", "been"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // I've
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // I have
    }

    func testMapsYouveContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["You've", "done"],
            synthesized: ["You", "have", "done"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // You've
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // You have
    }

    func testMapsWeveContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["We've", "arrived"],
            synthesized: ["We", "have", "arrived"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // We've
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // We have
    }

    func testMapsTheyveContraction() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["They've", "left"],
            synthesized: ["They", "have", "left"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // They've
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // They have
    }

    // MARK: - Possessive Tests

    func testMapsPossessiveSingle() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["John's", "book"],
            synthesized: ["John", "s", "book"]
        )

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // John's
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // John s
        XCTAssertEqual(mapping[1].displayIndices, [1])      // book
        XCTAssertEqual(mapping[1].synthesizedIndices, [2])
    }

    func testMapsPossessiveInSentence() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["The", "dog's", "tail"],
            synthesized: ["The", "dog", "s", "tail"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // dog's
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // dog s
    }

    func testMapsPossessiveWithNameEnding() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["James's", "car"],
            synthesized: ["James", "s", "car"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // James's
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1]) // James s
    }

    // MARK: - Number Tests

    func testMapsTwoDigitNumber() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Chapter", "23", "begins"],
            synthesized: ["Chapter", "twenty", "three", "begins"]
        )

        XCTAssertEqual(mapping.count, 3)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Chapter
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // 23
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // twenty three
        XCTAssertEqual(mapping[2].displayIndices, [2])      // begins
        XCTAssertEqual(mapping[2].synthesizedIndices, [3])
    }

    func testMapsSingleDigitNumber() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I", "have", "5", "apples"],
            synthesized: ["I", "have", "five", "apples"]
        )

        XCTAssertEqual(mapping[2].displayIndices, [2])      // 5
        XCTAssertEqual(mapping[2].synthesizedIndices, [2])   // five
    }

    func testMapsYear() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["In", "2024", "we"],
            synthesized: ["In", "two", "thousand", "twenty", "four", "we"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // 2024
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4]) // two thousand twenty four
    }

    func testMapsHundred() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["About", "100", "people"],
            synthesized: ["About", "one", "hundred", "people"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // 100
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2]) // one hundred
    }

    // MARK: - Technical Term Tests

    func testMapsTCPIPSlashNotation() {
        let mapper = TextNormalizationMapper()

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

    func testMapsHTTPHTTPSNotation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Use", "HTTP/HTTPS", "only"],
            synthesized: ["Use", "H", "T", "T", "P", "slash", "H", "T", "T", "P", "S", "only"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // HTTP/HTTPS
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) // H T T P slash H T T P S
    }

    // MARK: - Complex Mixed Cases

    func testMapsComplexSentenceWithMultipleNormalizations() {
        let mapper = TextNormalizationMapper()

        // "Dr. Smith's research couldn't work" - tests multiple normalization types
        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith's", "research", "couldn't", "work"],
            synthesized: ["Doctor", "Smith", "s", "research", "could", "not", "work"]
        )

        XCTAssertEqual(mapping.count, 5)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Dr. -> Doctor
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // Smith's -> Smith s
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2])
        XCTAssertEqual(mapping[2].displayIndices, [2])      // research -> research
        XCTAssertEqual(mapping[2].synthesizedIndices, [3])
        XCTAssertEqual(mapping[3].displayIndices, [3])      // couldn't -> could not
        XCTAssertEqual(mapping[3].synthesizedIndices, [4, 5])
        XCTAssertEqual(mapping[4].displayIndices, [4])      // work -> work
        XCTAssertEqual(mapping[4].synthesizedIndices, [6])
    }

    func testMapsAbbreviationPlusNumber() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Dr.", "Smith", "has", "5", "patients"],
            synthesized: ["Doctor", "Smith", "has", "five", "patients"]
        )

        XCTAssertEqual(mapping[0].displayIndices, [0])      // Dr. -> Doctor
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[3].displayIndices, [3])      // 5 -> five
        XCTAssertEqual(mapping[3].synthesizedIndices, [3])
    }

    func testMapsContractionPlusAbbreviation() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["I", "can't", "find", "Mr.", "Jones"],
            synthesized: ["I", "can", "not", "find", "Mister", "Jones"]
        )

        XCTAssertEqual(mapping[1].displayIndices, [1])      // can't -> can not
        XCTAssertEqual(mapping[1].synthesizedIndices, [1, 2])
        XCTAssertEqual(mapping[3].displayIndices, [3])      // Mr. -> Mister
        XCTAssertEqual(mapping[3].synthesizedIndices, [4])
    }

    // MARK: - Edge Cases

    func testMapsSingleWord() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["Hello"],
            synthesized: ["Hello"]
        )

        XCTAssertEqual(mapping.count, 1)
        XCTAssertEqual(mapping[0].displayIndices, [0])
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
    }

    func testMapsOneToManyExpansion() {
        let mapper = TextNormalizationMapper()

        let mapping = mapper.buildMapping(
            display: ["won't"],
            synthesized: ["will", "not"]
        )

        XCTAssertEqual(mapping.count, 1)
        XCTAssertEqual(mapping[0].displayIndices, [0])
        XCTAssertEqual(mapping[0].synthesizedIndices, [0, 1])
    }

    func testMapsCaseInsensitiveMatching() {
        let mapper = TextNormalizationMapper()

        // espeak might lowercase things
        let mapping = mapper.buildMapping(
            display: ["HELLO", "world"],
            synthesized: ["hello", "world"]
        )

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // HELLO -> hello
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
    }

    func testMapsPunctuationStripping() {
        let mapper = TextNormalizationMapper()

        // Display has punctuation, synthesized doesn't
        let mapping = mapper.buildMapping(
            display: ["Hello,", "world!"],
            synthesized: ["Hello", "world"]
        )

        XCTAssertEqual(mapping.count, 2)
        XCTAssertEqual(mapping[0].displayIndices, [0])      // Hello, -> Hello
        XCTAssertEqual(mapping[0].synthesizedIndices, [0])
        XCTAssertEqual(mapping[1].displayIndices, [1])      // world! -> world
        XCTAssertEqual(mapping[1].synthesizedIndices, [1])
    }

    func testMapsWithExtraWhitespace() {
        let mapper = TextNormalizationMapper()

        // Display might have extra spacing
        let mapping = mapper.buildMapping(
            display: ["Hello", "world"],
            synthesized: ["Hello", "world"]
        )

        XCTAssertEqual(mapping.count, 2)
    }
}

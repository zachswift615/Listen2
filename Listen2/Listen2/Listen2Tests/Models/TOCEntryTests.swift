//
//  TOCEntryTests.swift
//  Listen2Tests
//

import XCTest
@testable import Listen2

final class TOCEntryTests: XCTestCase {

    func testTOCEntryCreation() {
        let entry = TOCEntry(
            title: "Chapter 1: Introduction",
            paragraphIndex: 5,
            level: 0
        )

        XCTAssertEqual(entry.title, "Chapter 1: Introduction")
        XCTAssertEqual(entry.paragraphIndex, 5)
        XCTAssertEqual(entry.level, 0)
        XCTAssertNotNil(entry.id)
    }

    func testTOCEntryHierarchy() {
        let chapter = TOCEntry(title: "Chapter 1", paragraphIndex: 0, level: 0)
        let section = TOCEntry(title: "Section 1.1", paragraphIndex: 10, level: 1)
        let subsection = TOCEntry(title: "Subsection 1.1.1", paragraphIndex: 15, level: 2)

        XCTAssertEqual(chapter.level, 0)
        XCTAssertEqual(section.level, 1)
        XCTAssertEqual(subsection.level, 2)
    }
}

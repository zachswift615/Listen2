//
//  TOCEntry.swift
//  Listen2
//

import Foundation

struct TOCEntry: Identifiable, Hashable {
    let id: UUID
    let title: String
    let paragraphIndex: Int
    let level: Int // 0 = chapter, 1 = section, 2 = subsection

    init(title: String, paragraphIndex: Int, level: Int) {
        self.id = UUID()
        self.title = title
        self.paragraphIndex = paragraphIndex
        self.level = level
    }
}

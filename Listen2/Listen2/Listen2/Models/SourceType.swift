//
//  SourceType.swift
//  Listen2
//

import Foundation

enum SourceType: String, Codable {
    case pdf = "PDF"
    case epub = "EPUB"
    case clipboard = "Clipboard"

    var iconName: String {
        switch self {
        case .pdf: return "doc.fill"
        case .epub: return "book.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        }
    }
}

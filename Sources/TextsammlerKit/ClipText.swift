import Foundation

/// Text rules for copied snippets. No SwiftUI here, so tests run without the app.
public enum ClipText {
    /// One-line title for lists: whitespace collapsed, cut at `limit` characters.
    public static func title(_ text: String, limit: Int = 140) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    /// Repairs text copied from a PDF: lines inside a paragraph become one
    /// flowing line, words hyphenated at a line end are rejoined, and blank
    /// lines still separate paragraphs.
    public static func unwrap(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { paragraphs.append(current) }
            current = ""
        }
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if line.isEmpty {
                flush()
            } else if current.isEmpty {
                current = line
            } else if endsWithWordBreak(current), line.first?.isLowercase == true {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }
        }
        flush()
        return paragraphs.joined(separator: "\n\n")
    }

    /// Joins snippets in the given order. Empty snippets are skipped.
    public static func join(_ parts: [String], separator: String, unwrap: Bool) -> String {
        parts
            .map { unwrap ? Self.unwrap($0) : $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }

    /// "Zwischen-" at a line end, where the hyphen follows a letter.
    private static func endsWithWordBreak(_ text: String) -> Bool {
        guard text.last == "-" || text.last == "\u{00AD}" else { return false }
        return text.dropLast().last?.isLetter == true
    }
}

import Testing
@testable import TextsammlerKit

@Test("PDF line breaks are repaired", arguments: [
    ("Die Liefer-\nbedingungen gelten", "Die Lieferbedingungen gelten"),
    ("Zeile eins\nZeile zwei", "Zeile eins Zeile zwei"),
    ("Absatz eins\nweiter\n\nAbsatz zwei", "Absatz eins weiter\n\nAbsatz zwei"),
    ("Hin- und\nRückfahrt", "Hin- und Rückfahrt"),
    ("EAN-\nNummer", "EAN- Nummer"),
    ("  viele   Leerzeichen \r\n hier ", "viele Leerzeichen hier"),
])
func unwraps(_ input: String, expected: String) {
    #expect(ClipText.unwrap(input) == expected)
}

@Test func joinsInOrderAndSkipsEmpty() {
    #expect(ClipText.join(["A\nB", "  ", "C"], separator: "\n\n", unwrap: true) == "A B\n\nC")
    #expect(ClipText.join(["A\nB", "C "], separator: " ", unwrap: false) == "A\nB C")
}

@Test func titlesAreOneLine() {
    #expect(ClipText.title(" Erste\n  Zeile ") == "Erste Zeile")
    #expect(ClipText.title("abcdef", limit: 3) == "abc…")
}

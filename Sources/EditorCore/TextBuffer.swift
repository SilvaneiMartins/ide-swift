import Foundation

/// Posição visível ao usuário: linha e coluna 1-based, coluna contada em
/// unidades UTF-16 (mesma convenção do LSP, que é 0-based).
public struct TextPosition: Equatable, Sendable {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

/// Source of truth do texto de um documento.
///
/// Value type puro e `Sendable`: a UI (`NSTextView`) e as features (busca,
/// code actions, LSP) leem e escrevem aqui, nunca no text view. Todos os
/// offsets externos são UTF-16, porque é o que o LSP usa.
public struct TextBuffer: Sendable, Equatable {
    public private(set) var text: String

    /// Offset UTF-16 de início de cada linha, cacheado: o gutter chama
    /// `line(at:)` a cada frame.
    private var lineStarts: [Int]

    public init(text: String = "") {
        self.text = text
        self.lineStarts = Self.computeLineStarts(text)
    }

    // MARK: - Leitura

    public var isEmpty: Bool { text.isEmpty }
    public var utf16Count: Int { text.utf16.count }
    public var lineCount: Int { lineStarts.count }

    /// Offset UTF-16 de início de cada linha. O gutter e o realce sintático
    /// precisam disso a cada keystroke, então é a cache que justifica o array.
    public var lineStartOffsets: [Int] { lineStarts }

    /// Mesma coisa, para quando só existe o texto e não um `TextBuffer`
    /// (o `NSTextStorage` do editor).
    public static func lineStartOffsets(of text: String) -> [Int] {
        computeLineStarts(text)
    }

    /// Texto da linha sem o terminador. `line` é 1-based e clampado.
    public func line(at line: Int) -> String {
        let index = clampLine(line)
        let start = lineStarts[index]
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : utf16Count
        return substring(utf16: start..<end).droppingNewline
    }

    /// Linha completa, incluindo o terminador.
    public func rawLine(at line: Int) -> String {
        let index = clampLine(line)
        let start = lineStarts[index]
        let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : utf16Count
        return substring(utf16: start..<end)
    }

    /// Offset UTF-16 correspondente a uma linha/coluna visual (1-based).
    public func offset(forLine line: Int, column: Int) -> Int {
        let index = clampLine(line)
        let start = lineStarts[index]
        let lineEnd = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : utf16Count
        return min(start + max(column - 1, 0), lineEnd)
    }

    /// Posição visual de um offset UTF-16, por busca binária nas linhas.
    public func position(forUTF16Offset offset: Int) -> TextPosition {
        let clamped = min(max(offset, 0), utf16Count)
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= clamped {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return TextPosition(line: low + 1, column: clamped - lineStarts[low] + 1)
    }

    public func stringIndex(forUTF16Offset offset: Int) -> String.Index {
        let clamped = min(max(offset, 0), utf16Count)
        return text.utf16.index(text.utf16.startIndex, offsetBy: clamped)
    }

    public func utf16Offset(for index: String.Index) -> Int {
        text.utf16.distance(from: text.utf16.startIndex, to: index)
    }

    public func substring(utf16 range: Range<Int>) -> String {
        let lower = min(max(range.lowerBound, 0), utf16Count)
        let upper = min(max(range.upperBound, lower), utf16Count)
        // Índices de String (não de UTF16View): cortam em fronteira de
        // caractere, então nunca produzem Swift inválido nem metade de
        // um par substituto.
        return String(text[stringIndex(forUTF16Offset: lower)..<stringIndex(forUTF16Offset: upper)])
    }

    // MARK: - Escrita

    public mutating func replace(utf16 range: Range<Int>, with replacement: String) {
        let lower = min(max(range.lowerBound, 0), utf16Count)
        let upper = min(max(range.upperBound, lower), utf16Count)
        text.replaceSubrange(
            stringIndex(forUTF16Offset: lower)..<stringIndex(forUTF16Offset: upper),
            with: replacement
        )
        lineStarts = Self.computeLineStarts(text)
    }

    public mutating func setText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        lineStarts = Self.computeLineStarts(text)
    }

    // MARK: - Internos

    private func clampLine(_ line: Int) -> Int {
        min(max(line - 1, 0), lineStarts.count - 1)
    }

    private static func computeLineStarts(_ text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }
}

private extension String {
    /// Remove `\n` e `\r` finais: `\r\n` conta como um terminador só.
    /// Precisa iterar por `unicodeScalars` — em Swift "\r\n" é um único
    /// `Character` (grapheme cluster), então comparar com `last` nunca casa.
    var droppingNewline: String {
        var scalars = Array(unicodeScalars)
        while let last = scalars.last, last == "\n" || last == "\r" {
            scalars.removeLast()
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

import Foundation

/// Categoria de token para coloração. O mapeamento para cor fica na camada
/// de UI (`SyntaxTheme`), para o highlighter não depender de AppKit.
public enum TokenKind: Hashable, Sendable {
    case keyword
    case declarationKeyword
    case number
    case string
    case comment
    case docComment
    case attribute
    case type
    case function
    case property
    case operatorToken
    case identifier
}

/// Token com offsets UTF-16 relativos ao início da linha — é a mesma base
/// que o LSP usa, então a conversão para `NSTextView` é direta.
public struct Token: Hashable, Sendable {
    public let range: Range<Int>
    public let kind: TokenKind

    public init(range: Range<Int>, kind: TokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// Tokens de uma linha, sem o terminador. Unidade de diff: só as linhas
/// cujos tokens mudaram são re-renderizadas no editor.
public struct LineTokens: Hashable, Sendable {
    public let tokens: [Token]

    public init(tokens: [Token]) {
        self.tokens = tokens
    }
}

/// Conjunto de tokens de um arquivo, indexado por linha 0-based.
public struct HighlightResult: Sendable {
    public let lines: [LineTokens]

    public init(lines: [LineTokens]) {
        self.lines = lines
    }

    /// Faixa de linhas que o editor precisa repintar: da primeira que mudou
    /// até o fim do arquivo.
    ///
    /// É conservadora de propósito. Um construct multilinha (string ou
    /// comentário aberto) muda o sentido do token na linha seguinte, então
    /// cortar na primeira diferença erraria a coloração. O custo é baixo
    /// porque a repintura é só aplicação de atributos, não parse.
    public static func changedLines(from old: HighlightResult, to new: HighlightResult) -> Range<Int> {
        let shared = min(old.lines.count, new.lines.count)
        var firstChanged = shared
        for index in 0..<shared where old.lines[index] != new.lines[index] {
            firstChanged = index
            break
        }
        if old.lines.count == new.lines.count { return firstChanged..<shared }
        return firstChanged..<max(old.lines.count, new.lines.count)
    }
}

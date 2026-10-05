import Foundation
import SwiftParser
import SwiftSyntax

/// Realce sintático de Swift via swift-syntax.
///
/// Roda fora da main thread: a digitação não espera o parse. O resultado
/// é uma lista de tokens por linha e o editor só repinta as linhas que
/// realmente mudaram — é isso que mantém a digitação fluida em arquivos
/// grandes.
public enum SwiftSourceHighlighter {
    public static func highlight(_ text: String) -> HighlightResult {
        let lines = splitLines(text)
        guard !lines.isEmpty else { return HighlightResult(lines: []) }

        let lineStarts = utf8StartOffsets(of: lines)
        let source = Parser.parse(source: text)
        let converter = SourceLocationConverter(fileName: "", tree: source)

        var raw: [RawToken] = []
        var afterAttributeMarker = false

        for token in source.tokens(viewMode: .sourceAccurate) {
            // Comentários são trivia, não tokens — precisam de varredura à parte.
            raw.append(contentsOf: triviaTokens(token, converter: converter))

            guard let kind = lexicalKind(token, afterAttributeMarker: afterAttributeMarker) else {
                afterAttributeMarker = false
                continue
            }
            afterAttributeMarker = token.tokenKind == .atSign

            if let range = tokenRange(token) {
                let line = converter.location(for: AbsolutePosition(utf8Offset: range.lowerBound)).line - 1
                raw.append(RawToken(line: line, utf8Range: range, kind: kind))
            }
        }

        let declarations = DeclarationVisitor(converter: converter)
        declarations.walk(source)
        for declaration in declarations.found {
            raw.append(RawToken(line: declaration.line, utf8Range: declaration.range, kind: declaration.kind))
        }

        // Resolve linha e converte UTF-8 -> UTF-16 por linha.
        var perLine = Array(repeating: [Token](), count: lines.count)
        for entry in raw {
            let line = entry.line
            guard line >= 0, line < lines.count else { continue }
            let map = LineOffsetMap(line: lines[line], absoluteUTF8Start: lineStarts[line])
            guard let converted = map.convert(entry.utf8Range) else { continue }
            perLine[line].append(Token(range: converted, kind: entry.kind))
        }

        for index in perLine.indices {
            perLine[index] = resolveOverlaps(perLine[index])
        }
        return HighlightResult(lines: perLine.map { LineTokens(tokens: $0) })
    }

    // MARK: - Classificação léxica

    /// Keywords são classificadas pelo texto, não por `Keyword` do
    /// swift-syntax: aquele enum cresce a cada versão do Swift e quebraria
    /// o build numa atualização.
    static let declarationKeywords: Set<String> = [
        "func", "var", "let", "struct", "class", "enum", "protocol", "extension",
        "typealias", "actor", "init", "deinit", "subscript", "case", "import",
        "macro", "associatedtype", "precedencegroup", "operator",
    ]

    private static func lexicalKind(_ token: TokenSyntax, afterAttributeMarker: Bool) -> TokenKind? {
        if afterAttributeMarker, case .identifier = token.tokenKind { return .attribute }

        switch token.tokenKind {
        case .keyword:
            return declarationKeywords.contains(token.text) ? .declarationKeyword : .keyword
        case .integerLiteral, .floatLiteral:
            return .number
        case .stringSegment, .stringQuote, .multilineStringQuote, .singleQuote,
             .rawStringPoundDelimiter, .regexLiteralPattern, .regexPoundDelimiter, .regexSlash:
            return .string
        case .atSign:
            return .attribute
        case .identifier:
            return .identifier
        case .prefixOperator, .postfixOperator, .binaryOperator, .prefixAmpersand,
             .exclamationMark, .backtick:
            return .operatorToken
        default:
            return nil
        }
    }

    /// Comentários vivem no trivia de cada token, não na lista de tokens.
    private static func triviaTokens(_ token: TokenSyntax, converter: SourceLocationConverter) -> [RawToken] {
        var found: [RawToken] = []
        var offset = token.position.utf8Offset

        for piece in token.leadingTrivia {
            let length = piece.utf8Length
            switch piece {
            case .lineComment, .blockComment, .docLineComment, .docBlockComment:
                let line = converter.location(for: AbsolutePosition(utf8Offset: offset)).line - 1
                let kind: TokenKind = piece.isDocumentation ? .docComment : .comment
                found.append(RawToken(line: line, utf8Range: offset..<(offset + length), kind: kind))
            default:
                break
            }
            offset += length
        }
        return found
    }

    private static func tokenRange(_ token: TokenSyntax) -> Range<Int>? {
        let start = token.positionAfterSkippingLeadingTrivia
        let end = token.endPositionBeforeTrailingTrivia
        guard end.utf8Offset > start.utf8Offset else { return nil }
        return start.utf8Offset..<end.utf8Offset
    }

    /// Tokens do lexer e do visitor de declarações cobrem o mesmo trecho
    /// (o nome de uma função é `.identifier` e `.function`). Mantém só o de
    /// maior prioridade.
    ///
    /// A ordem é por posição, não por prioridade: só assim o descarte de
    /// sobreposição pode ser um cursor sequencial. Ordenando por prioridade,
    /// um token sobreposto passaria pelo teste contra o anterior errado.
    private static func resolveOverlaps(_ tokens: [Token]) -> [Token] {
        let ordered = tokens.sorted { lhs, rhs in
            if lhs.range.lowerBound != rhs.range.lowerBound {
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            if lhs.kind.priority != rhs.kind.priority {
                return lhs.kind.priority > rhs.kind.priority
            }
            return lhs.range.upperBound > rhs.range.upperBound
        }
        var kept: [Token] = []
        var cursor = Int.min
        for token in ordered {
            guard token.range.lowerBound >= cursor else { continue }
            kept.append(token)
            cursor = token.range.upperBound
        }
        return kept
    }

    // MARK: - Linhas e offsets

    /// Divide em linhas sem o `\n`.
    static func splitLines(_ text: String) -> [Substring] {
        var lines: [Substring] = []
        var start = text.startIndex
        for index in text.indices where text[index] == "\n" {
            lines.append(text[start..<index])
            start = text.index(after: index)
        }
        lines.append(text[start...])
        return lines
    }

    private static func utf8StartOffsets(of lines: [Substring]) -> [Int] {
        var starts: [Int] = []
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.utf8.count + 1
        }
        return starts
    }
}

// MARK: - Modelo interno

struct RawToken {
    var line: Int
    var utf8Range: Range<Int>
    var kind: TokenKind
}

extension TokenKind {
    /// Maior vence quando dois tokens cobrem o mesmo trecho.
    var priority: Int {
        switch self {
        case .comment, .docComment: return 100
        case .string, .number, .attribute: return 90
        case .keyword, .declarationKeyword: return 80
        case .type, .function, .property: return 70
        case .identifier, .operatorToken: return 10
        }
    }
}

// MARK: - Mapa de offsets

/// Converte offsets UTF-8 absolutos para offsets UTF-16 dentro da linha.
///
/// Existe porque swift-syntax trabalha em UTF-8 e o `NSTextStorage` em
/// UTF-16. Converter em vez de assumir é o que mantém acentuação e emoji
/// (fora do BMP, 2 unidades UTF-16) alinhados com o texto real.
struct LineOffsetMap {
    private let scalars: [Unicode.Scalar]
    private let lineStartUTF8: Int

    init(line: Substring, absoluteUTF8Start: Int) {
        self.scalars = Array(line.unicodeScalars)
        self.lineStartUTF8 = absoluteUTF8Start
    }

    func convert(_ absoluteUTF8Range: Range<Int>) -> Range<Int>? {
        guard let lower = utf16Offset(forUTF8: absoluteUTF8Range.lowerBound),
              let upper = utf16Offset(forUTF8: absoluteUTF8Range.upperBound),
              upper > lower else { return nil }
        return lower..<upper
    }

    private func utf16Offset(forUTF8 absolute: Int) -> Int? {
        let target = absolute - lineStartUTF8
        guard target >= 0 else { return nil }
        var utf8 = 0
        var utf16 = 0
        for scalar in scalars {
            if utf8 == target { return utf16 }
            utf8 += scalar.utf8.count
            utf16 += scalar.utf16.count
        }
        return utf8 == target ? utf16 : nil
    }
}

extension TriviaPiece {
    /// `///` e `/** */` são documentação; `//` e `/* */` são comentário comum.
    var isDocumentation: Bool {
        switch self {
        case .docLineComment, .docBlockComment: true
        default: false
        }
    }

    /// `Trivia` não expõe comprimento; os textos vêm prontos e as
    /// repetições são contagens, então compõe-se direto.
    var utf8Length: Int {
        switch self {
        case .backslashes(let count): return count * "\\".utf8.count
        case .blockComment(let text), .docBlockComment(let text),
             .docLineComment(let text), .lineComment(let text),
             .unexpectedText(let text):
            return text.utf8.count
        case .carriageReturns(let count): return count
        case .carriageReturnLineFeeds(let count): return count * 2
        case .formfeeds(let count): return count
        case .newlines(let count): return count
        case .pounds(let count): return count
        case .spaces(let count): return count
        case .tabs(let count): return count * 1
        case .verticalTabs(let count): return count
        }
    }
}

// MARK: - Declarações

/// Nomes de tipos, funções e propriedades exigem o tree, não só o lexer.
/// É o que dá cara de IDE em vez de coloridor de texto.
private final class DeclarationVisitor: SyntaxVisitor {
    struct Declaration {
        let line: Int
        let range: Range<Int>
        let kind: TokenKind
    }

    private(set) var found: [Declaration] = []
    private let converter: SourceLocationConverter

    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func record(_ name: some SyntaxProtocol?, as kind: TokenKind) {
        guard let name = name?.as(TokenSyntax.self) else { return }
        let start = name.positionAfterSkippingLeadingTrivia
        let end = name.endPositionBeforeTrailingTrivia
        guard end.utf8Offset > start.utf8Offset else { return }
        found.append(
            Declaration(
                line: converter.location(for: start).line - 1,
                range: start.utf8Offset..<end.utf8Offset,
                kind: kind
            )
        )
    }

    /// Não existe um `TypeDeclSyntax`: cada kind de tipo é um nó concreto,
    /// e o `SyntaxVisitor` desta versão não tem `visitAny`. Um método por
    /// tipo é o jeito idiomático.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .type)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .type)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .type)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .type)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .type)
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .type)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.extendedType, as: .type)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name, as: .function)
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                record(identifier.identifier, as: .property)
            }
        }
        return .visitChildren
    }
}

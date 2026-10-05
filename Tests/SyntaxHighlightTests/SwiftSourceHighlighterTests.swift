import Testing

@testable import SyntaxHighlight

@Suite("SwiftSourceHighlighter")
struct SwiftSourceHighlighterTests {
    /// Atalho: kind do primeiro token da linha, para os testes ficarem legíveis.
    private func kinds(inLine index: Int, of result: HighlightResult) -> [TokenKind] {
        result.lines[index].tokens.map(\.kind)
    }

    @Test("divide linhas preservando a última linha vazia")
    func lineSplitting() {
        let lines = SwiftSourceHighlighter.splitLines("a\nb\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "a")
        #expect(lines[2] == "")
    }

    @Test("keyword de declaração difere de keyword de fluxo")
    func keywordClassification() {
        let result = SwiftSourceHighlighter.highlight("func soma() { return 1 }")
        let tokens = result.lines[0].tokens
        #expect(tokens.first { $0.range.lowerBound == 0 }?.kind == .declarationKeyword)
        #expect(tokens.contains { $0.kind == .declarationKeyword })
        #expect(tokens.contains { $0.kind == .keyword })
    }

    @Test("nomes de função e tipo vêm do tree, não do lexer")
    func declarationNames() {
        let result = SwiftSourceHighlighter.highlight("struct Cliente { func saudar() {} }")
        let tokens = result.lines[0].tokens
        #expect(tokens.contains { $0.kind == .type })
        #expect(tokens.contains { $0.kind == .function })
        // o mesmo trecho não aparece duas vezes
        #expect(Set(tokens.map(\.range)).count == tokens.count)
    }

    @Test("comentário é trivia, /// é documentação")
    func comments() {
        let result = SwiftSourceHighlighter.highlight("// nota\n/// doc\nlet x = 1")
        #expect(kinds(inLine: 0, of: result).contains(.comment))
        #expect(kinds(inLine: 1, of: result).contains(.docComment))
    }

    @Test("string, número e atributo")
    func literals() {
        let result = SwiftSourceHighlighter.highlight("@MainActor\nlet n = 42\nlet s = \"oi\"")
        #expect(kinds(inLine: 0, of: result).contains(.attribute))
        #expect(kinds(inLine: 1, of: result).contains(.number))
        #expect(kinds(inLine: 2, of: result).contains(.string))
    }

    @Test("offsets são UTF-16, então acento e emoji não deslocam o token")
    func utf16Offsets() {
        let result = SwiftSourceHighlighter.highlight("let café = \"🎉\"\nlet b = 2")
        // "let café" -> 'café' ocupa 4 unidades UTF-16 (c a f é)
        let property = result.lines[0].tokens.first { $0.kind == .property }
        #expect(property?.range == 4..<8)
        // 🎉 ocupa 2 unidades UTF-16
        let second = result.lines[1].tokens.first { $0.kind == .property }
        #expect(second?.range == 4..<5)
    }

    @Test("string multilinha colore cada linha como string")
    func multilineString() {
        let result = SwiftSourceHighlighter.highlight("let s = \"\"\"\nabc\n\"\"\"")
        #expect(kinds(inLine: 1, of: result).contains(.string))
    }

    @Test("highlight de arquivo longo devolve uma linha por linha do arquivo")
    func lineCountMatches() {
        let source = (0..<300).map { "let valor\($0) = \($0)" }.joined(separator: "\n")
        let result = SwiftSourceHighlighter.highlight(source)
        #expect(result.lines.count == 300)
    }

    @Test("diff começa na primeira linha que mudou e vai até o fim")
    func changedLines() {
        let before = SwiftSourceHighlighter.highlight("let a = 1\nlet b = 2\nlet c = 3\nlet d = 4")
        let after = SwiftSourceHighlighter.highlight("let a = 1\nlet b = 2\nlet c = 99\nlet d = 4")
        #expect(HighlightResult.changedLines(from: before, to: after) == 2..<4)
    }

    @Test("texto idêntico não repinta nada")
    func noChange() {
        let before = SwiftSourceHighlighter.highlight("let a = 1")
        let after = SwiftSourceHighlighter.highlight("let a = 1")
        #expect(HighlightResult.changedLines(from: before, to: after).isEmpty)
    }

    @Test("diff detecta linhas adicionadas e removidas")
    func changedLinesWhenLineCountDiffers() {
        let before = SwiftSourceHighlighter.highlight("let a = 1")
        let after = SwiftSourceHighlighter.highlight("let a = 1\nlet b = 2")
        #expect(HighlightResult.changedLines(from: before, to: after) == 1..<2)
    }
}

import Testing

@testable import EditorCore

@Suite("TextBuffer")
struct TextBufferTests {
    @Test("linhas accountam terminadores CRLF e LF")
    func lineCounting() {
        let buffer = TextBuffer(text: "let a = 1\nlet b = 2\nlet c = 3")
        #expect(buffer.lineCount == 3)
        #expect(buffer.line(at: 1) == "let a = 1")
        #expect(buffer.line(at: 3) == "let c = 3")
    }

    @Test("linha final termina com newline gera linha vazia extra")
    func trailingNewline() {
        let buffer = TextBuffer(text: "a\n")
        #expect(buffer.lineCount == 2)
        #expect(buffer.line(at: 2) == "")
    }

    @Test("offset de linha/coluna é 1-based")
    func offsetForPosition() {
        let buffer = TextBuffer(text: "abc\ndefg\nhi")
        #expect(buffer.offset(forLine: 1, column: 1) == 0)
        #expect(buffer.offset(forLine: 2, column: 1) == 4)
        #expect(buffer.offset(forLine: 2, column: 3) == 6)
    }

    @Test("posição de offset usa busca binária nas linhas")
    func positionForOffset() {
        let buffer = TextBuffer(text: "abc\ndefg\nhi")
        #expect(buffer.position(forUTF16Offset: 0) == TextPosition(line: 1, column: 1))
        #expect(buffer.position(forUTF16Offset: 4) == TextPosition(line: 2, column: 1))
        #expect(buffer.position(forUTF16Offset: 9) == TextPosition(line: 3, column: 1))
        #expect(buffer.position(forUTF16Offset: 11) == TextPosition(line: 3, column: 3))
    }

    @Test("ida e volta entre offset e String.Index é estável")
    func roundTrip() {
        let buffer = TextBuffer(text: "let x = \"emoji 🎉\"\nprint(x)")
        let index = buffer.stringIndex(forUTF16Offset: 4)
        #expect(buffer.utf16Offset(for: index) == 4)
        // 🎉 ocupa 2 unidades UTF-16
        #expect(buffer.utf16Count == buffer.text.utf16.count)
    }

    @Test("replace por faixa UTF-16 recálcula as linhas")
    func replaceRange() {
        var buffer = TextBuffer(text: "let a = 1")
        buffer.replace(utf16: 4..<5, with: "value")
        #expect(buffer.text == "let value = 1")
        #expect(buffer.lineCount == 1)
    }

    @Test("insert com newline cria novas linhas")
    func replaceIntroducingNewline() {
        var buffer = TextBuffer(text: "ab")
        buffer.replace(utf16: 1..<1, with: "\n")
        #expect(buffer.lineCount == 2)
        #expect(buffer.line(at: 1) == "a")
        #expect(buffer.line(at: 2) == "b")
    }

    @Test("outros fora dos limites são clampados, não crasham")
    func clamping() {
        let buffer = TextBuffer(text: "abc")
        #expect(buffer.position(forUTF16Offset: 999) == TextPosition(line: 1, column: 4))
        #expect(buffer.position(forUTF16Offset: -5) == TextPosition(line: 1, column: 1))
        #expect(buffer.line(at: 42) == "abc")
        #expect(buffer.offset(forLine: 1, column: 99) == 3)
    }

    @Test("CRLF é tratado como um único terminador")
    func crlf() {
        let buffer = TextBuffer(text: "a\r\nb")
        #expect(buffer.lineCount == 2)
        #expect(buffer.line(at: 1) == "a")
        #expect(buffer.line(at: 2) == "b")
    }
}

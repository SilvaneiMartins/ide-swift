import AppKit
import Testing

@testable import EditorCore

/// `toggleComment` só existe no `NSTextView`, então o teste monta um editor
/// de verdade. Precisa de main actor e de um window para responder a
/// first responder.
@Suite("EditorTextView")
@MainActor
struct EditorTextViewTests {
    private func makeEditor(_ text: String) -> (EditorTextView, CodeEditorContainerView) {
        // Sem window: nenhuma das operações testadas precisa de uma, e criar
        // janelas AppKit em teste derrubado o processo com signal 11.
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.string = text
        return (textView, CodeEditorContainerView(textView: textView))
    }

    private func selectLines(_ textView: NSTextView, from start: Int, to end: Int) {
        let nsString = textView.string as NSString
        textView.setSelectedRange(nsString.lineRange(for: NSRange(location: start, length: 0)))
        _ = end
    }

    @Test("comenta a linha do cursor preservando indentação")
    func commentSingleLine() {
        let (textView, container) = makeEditor("    let a = 1")
        selectLines(textView, from: 0, to: 0)
        container.toggleComment()
        #expect(textView.string == "    // let a = 1")
    }

    @Test("comenta múltiplas linhas com indentação própria de cada uma")
    func commentMultipleLines() {
        let (textView, container) = makeEditor("let a = 1\n    let b = 2\nlet c = 3")
        let nsString = textView.string as NSString
        textView.setSelectedRange(NSRange(location: 0, length: nsString.length))
        container.toggleComment()
        #expect(textView.string == "// let a = 1\n    // let b = 2\n// let c = 3")
    }

    @Test("descomenta quando todas as linhas já estão comentadas")
    func uncommentAll() {
        let (textView, container) = makeEditor("// let a = 1\n    // let b = 2")
        let nsString = textView.string as NSString
        textView.setSelectedRange(NSRange(location: 0, length: nsString.length))
        container.toggleComment()
        #expect(textView.string == "let a = 1\n    let b = 2")
    }

    @Test("linhas vazias no meio não quebram o comentário")
    func skipsBlankLines() {
        let (textView, container) = makeEditor("let a = 1\n\nlet b = 2")
        let nsString = textView.string as NSString
        textView.setSelectedRange(NSRange(location: 0, length: nsString.length))
        container.toggleComment()
        #expect(textView.string == "// let a = 1\n\n// let b = 2")
    }

    @Test("comentar e descomentar é ida e volta")
    func roundTrip() {
        let (textView, container) = makeEditor("    let a = 1\nlet b = 2")
        let nsString = textView.string as NSString
        textView.setSelectedRange(NSRange(location: 0, length: nsString.length))

        container.toggleComment()
        let commented = textView.string
        container.toggleComment()
        #expect(textView.string == "    let a = 1\nlet b = 2")
        #expect(commented != textView.string)
    }

    @Test("goToLine posiciona o cursor no início da linha pedida")
    func goToLine() {
        let (textView, container) = makeEditor("a\nb\nc\nd")
        container.goToLine(3)
        #expect(textView.selectedRange().location == 4)
    }

    @Test("goToLine fora do intervalo vai para a última linha")
    func goToLineOutOfRange() {
        let (textView, container) = makeEditor("a\nb\nc")
        container.goToLine(99)
        #expect(textView.selectedRange().location == 4)
    }
}

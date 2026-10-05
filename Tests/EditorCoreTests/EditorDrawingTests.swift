import AppKit
import Testing

@testable import EditorCore

/// O gutter e a faixa de linha atual só podem ser validados desenhando de
/// verdade: exercitar layout e `draw(_:)` num view sem window é o jeito mais
/// próximo de "rodar o editor" que um teste de CLI consegue fazer.
@Suite("EditorDrawing")
@MainActor
struct EditorDrawingTests {
    private func makeEditor(_ text: String) -> (EditorTextView, CodeEditorContainerView) {
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = text
        let container = CodeEditorContainerView(textView: textView)
        container.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        container.layoutSubtreeIfNeeded()
        return (textView, container)
    }

    /// Renderiza a view num bitmap e devolve a contagem de pixels não
    /// transparentes. Zero significa que nada foi desenhado.
    private func renderedPixelCount(_ view: NSView) -> Int {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: representation)

        var nonTransparent = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                if let color = representation.colorAt(x: x, y: y), color.alphaComponent > 0.01 {
                    nonTransparent += 1
                }
            }
        }
        return nonTransparent
    }

    @Test("o editor desenha conteúdo visível")
    func editorDraws() {
        let (_, container) = makeEditor("let a = 1\nlet b = 2")
        #expect(renderedPixelCount(container) > 0)
    }

    @Test("o gutter tem pixels na faixa da esquerda, onde ficam os números")
    func gutterDrawsNumbers() {
        let (_, container) = makeEditor("let a = 1\nlet b = 2")
        let image = renderedBitmap(container)
        let gutterWidth = 56
        #expect(nonTransparentPixels(image, inXRange: 0..<gutterWidth) > 0)
    }

    /// O retângulo é o contrato que `drawBackground(in:)` consome. O pixel
    /// em si não é verificável aqui: o TextKit só rasteriza com uma window
    /// anexada, então `cacheDisplay` devolve fundo vazio.
    @Test("a faixa da linha atual acompanha a linha do cursor")
    func currentLineRectFollowsCursor() {
        let (textView, container) = makeEditor("let a = 1\nlet b = 2\nlet c = 3")
        container.updateCurrentLine()

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        container.updateCurrentLine()
        let first = try! #require(textView.currentLineRect)

        textView.setSelectedRange(NSRange(location: 16, length: 0))
        container.updateCurrentLine()
        let third = try! #require(textView.currentLineRect)

        #expect(first.minY == 0)
        #expect(third.minY > first.minY)
        #expect(third.maxY <= textView.bounds.height)
    }

    @Test("a faixa cobre a largura toda, não só os caracteres")
    func currentLineRectSpansWidth() {
        let (textView, container) = makeEditor("x")
        container.updateCurrentLine()
        let rect = try! #require(textView.currentLineRect)
        #expect(rect.minX == 0)
        #expect(rect.width >= textView.bounds.width)
    }

    @Test("a faixa não se move quando a seleção anda dentro da mesma linha")
    func currentLineRectStableWithinLine() {
        let (textView, container) = makeEditor("let a = 1\nlet b = 2")
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        container.updateCurrentLine()
        let atStart = try! #require(textView.currentLineRect)

        textView.setSelectedRange(NSRange(location: 4, length: 0))
        container.updateCurrentLine()
        let atEnd = try! #require(textView.currentLineRect)

        #expect(atStart == atEnd)
    }

    @Test("documento vazio não gera faixa")
    func noRectWhenEmpty() {
        let (textView, container) = makeEditor("")
        container.updateCurrentLine()
        #expect(textView.currentLineRect == nil)
    }

    // MARK: - Helpers de bitmap

    private func renderedBitmap(_ view: NSView) -> NSBitmapImageRep? {
        view.bitmapImageRepForCachingDisplay(in: view.bounds).map {
            view.cacheDisplay(in: view.bounds, to: $0)
            return $0
        }
    }

    private func nonTransparentPixels(_ image: NSBitmapImageRep?, inXRange range: Range<Int>) -> Int {
        guard let image else { return 0 }
        var count = 0
        for y in 0..<image.pixelsHigh {
            for x in range where x < image.pixelsWide {
                if image.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.01 { count += 1 }
            }
        }
        return count
    }

    /// Amostra um ponto no meio da faixa de texto da linha, longe do gutter.
}

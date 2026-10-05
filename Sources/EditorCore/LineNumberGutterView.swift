import AppKit
import DesignSystem

/// Gutter de números de linha.
///
/// Desenhado à mão em vez de `NSRulerView`: ruler não acompanha bem o
/// `lineFragmentPadding = 0` do editor, e o gutter precisa de marcadores de
/// erro por linha (Fase 2) no mesmo espaço.
final class LineNumberGutterView: NSView {
    struct Marker {
        enum Kind { case error, warning }
        let kind: Kind
    }

    /// Marcadores por linha 0-based.
    var markers: [Int: Marker] = [:]

    private weak var textView: NSTextView?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Metrics.gutterWidth, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let storage = textView.textStorage,
              storage.length > 0 else { return }

        let lineStarts = TextBuffer.lineStartOffsets(of: storage.string)
        let currentLine = self.currentLine(in: textView, lineStarts: lineStarts)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: EditorFont.mono(size: EditorFont.defaultSize - 1),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: EditorFont.mono(size: EditorFont.defaultSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath()
        border.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        border.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        border.lineWidth = 1
        border.stroke()

        let inset = textView.textContainerInset.height

        for line in 0..<lineStarts.count {
            let characterIndex = lineStarts[line]
            let glyphIndex = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: characterIndex, length: 0),
                actualCharacterRange: nil
            ).location
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let baseline = fragment.minY + inset

            guard baseline + 16 >= dirtyRect.minY, baseline - 4 <= dirtyRect.maxY else { continue }

            if let marker = markers[line] {
                let color: NSColor = marker.kind == .error ? .systemRed : .systemYellow
                color.setFill()
                let diameter: CGFloat = 7
                NSBezierPath(ovalIn: NSRect(x: 5, y: baseline - 1, width: diameter, height: diameter)).fill()
            }

            let label = NSString(string: "\(line + 1)")
            let attributes = line == currentLine ? currentAttributes : textAttributes
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.maxX - 6 - size.width, y: baseline), withAttributes: attributes)
        }
    }

    /// Índice 0-based da linha onde está a seleção.
    private func currentLine(in textView: NSTextView, lineStarts: [Int]) -> Int? {
        let location = textView.selectedRange().location
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

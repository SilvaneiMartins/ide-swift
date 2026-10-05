import AppKit
import DesignSystem
import SyntaxHighlight
import SwiftUI

/// Editor de código: `NSTextView` + gutter, dentro de `NSViewRepresentable`.
///
/// É o único lugar do app que fala com a `NSTextView`. Todo o resto passa
/// pelo `TextBuffer`, que é o source of truth do texto.
public struct CodeEditorView: NSViewRepresentable {
    @Binding public var text: String
    public var fontSize: CGFloat
    public var isEditable: Bool
    public var undoCoalescingInterval: TimeInterval
    public var onSelectionChange: (TextPosition) -> Void
    /// Recebe o container assim que ele existe, para os menus do SwiftUI
    /// (`⌃L`, `⌘/`, `⌘F`) alcançarem o `NSTTextView`.
    public var onContainerReady: ((CodeEditorContainerView) -> Void)?

    public init(
        text: Binding<String>,
        fontSize: CGFloat = EditorFont.defaultSize,
        isEditable: Bool = true,
        undoCoalescingInterval: TimeInterval = 0.6,
        onSelectionChange: @escaping (TextPosition) -> Void = { _ in },
        onContainerReady: ((CodeEditorContainerView) -> Void)? = nil
    ) {
        self._text = text
        self.fontSize = fontSize
        self.isEditable = isEditable
        self.undoCoalescingInterval = undoCoalescingInterval
        self.onSelectionChange = onSelectionChange
        self.onContainerReady = onContainerReady
    }

    public func makeNSView(context: Context) -> CodeEditorContainerView {
        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.string = text
        textView.font = EditorFont.mono(size: fontSize)

        let container = CodeEditorContainerView(textView: textView)
        context.coordinator.attach(to: textView, container: container)
        context.coordinator.undoCoalescingInterval = undoCoalescingInterval
        context.coordinator.onSelectionChange = onSelectionChange
        onContainerReady?(container)
        return container
    }

    public func updateNSView(_ container: CodeEditorContainerView, context: Context) {
        let textView = container.textView
        textView.isEditable = isEditable
        let font = EditorFont.mono(size: fontSize)
        if textView.font != font { textView.font = font }
        context.coordinator.undoCoalescingInterval = undoCoalescingInterval
        context.coordinator.onSelectionChange = onSelectionChange

        // Só escreve no text view quando o buffer mudou por fora: durante a
        // digitação, sobrescrever tiraria o cursor de lugar a cada tecla.
        if textView.string != text, context.coordinator.shouldAcceptExternalText(text) {
            let selection = textView.selectedRange()
            let origin = container.scrollView.contentView.bounds.origin
            textView.string = text
            textView.setSelectedRange(selection)
            container.scrollView.contentView.scroll(to: origin)
            textView.resetAttributes()
            context.coordinator.lastPushedText = text
            context.coordinator.requestHighlight()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        var onSelectionChange: (TextPosition) -> Void = { _ in }
        var undoCoalescingInterval: TimeInterval = 0.6 {
            didSet { textView?.undoCoalescingInterval = undoCoalescingInterval }
        }

        /// Último texto que o editor empurrou para o `NSTextView`. É o que
        /// distingue "o usuário digitou" de "o buffer mudou por fora", sem
        /// depender de um flag `isTyping` que fica preso quando a edição
        /// termina sem passar por `textDidEndEditing`.
        var lastPushedText: String?
        private weak var textView: EditorTextView?
        private weak var container: CodeEditorContainerView?
        private var previousHighlight: HighlightResult?
        private var highlightWork: Task<Void, Never>?
        private var highlightGeneration = 0

        init(text: Binding<String>) {
            self._text = text
        }

        func attach(to textView: EditorTextView, container: CodeEditorContainerView) {
            self.textView = textView
            self.container = container
            textView.undoCoalescingInterval = undoCoalescingInterval
            lastPushedText = textView.string
            requestHighlight()
        }

        /// Verdadeiro quando `text` não veio do próprio `NSTextView` — ou
        /// seja, o documento foi trocado ou o buffer foi editado fora dele.
        func shouldAcceptExternalText(_ text: String) -> Bool {
            text != lastPushedText
        }

        // MARK: - NSTextViewDelegate

        public func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            lastPushedText = textView.string
            requestHighlight()
            container?.updateCurrentLine()
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            onSelectionChange(TextBuffer(text: textView.string).position(forUTF16Offset: textView.selectedRange().location))
            container?.updateCurrentLine()
        }

        // MARK: - Realce sintático

        /// O parse roda fora da main thread — a digitação não espera por ele.
        /// A geração descarta resultados obsoletos: sem isso, um highlight
        /// antigo chega depois do novo e a cor pisca.
        func requestHighlight() {
            guard let textView else { return }
            highlightGeneration += 1
            let generation = highlightGeneration
            let snapshot = textView.string

            highlightWork?.cancel()
            highlightWork = Task { [weak self, weak textView] in
                let result = await Task.detached(priority: .userInitiated) {
                    SwiftSourceHighlighter.highlight(snapshot)
                }.value

                guard !Task.isCancelled, let self, let textView else { return }
                guard generation == self.highlightGeneration else { return }
                self.applyHighlight(result, to: textView)
            }
        }

        private func applyHighlight(_ result: HighlightResult, to textView: EditorTextView) {
            let changed = HighlightResult.changedLines(from: previousHighlight ?? HighlightResult(lines: []), to: result)
            previousHighlight = result
            guard !changed.isEmpty, let storage = textView.textStorage else { return }

            SyntaxTheme.apply(
                result.lines,
                lineStarts: TextBuffer.lineStartOffsets(of: storage.string),
                changedRange: changed,
                to: storage,
                baseFont: textView.font ?? EditorFont.mono()
            )
            container?.textViewDidChangeLayout()
        }
    }
}

/// Precisa ficar em extension: é um optional requirement do
/// `NSTextViewDelegate`, e o compilador só o associa fora da classe.
extension CodeEditorView.Coordinator {
    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn ranges: [NSRange],
        replacementString string: String
    ) -> Bool {
        (textView as? EditorTextView)?.registerEdit()
        return true
    }
}

/// `NSTextView` com undo agrupado por rajada de digitação.
///
/// O grupo fica aberto durante a rajada e é fechado por timer. Se ficasse
/// aberto esperando a próxima tecla, o primeiro Cmd-Z só fecharia o grupo
/// e não desfaria nada.
public final class EditorTextView: NSTextView {
    var undoCoalescingInterval: TimeInterval = 0.6 {
        didSet {
            lastEditDate = nil
            closeUndoGroup()
        }
    }

    private var lastEditDate: Date?
    private var isUndoGroupOpen = false
    private var closeGroupTimer: Timer?

    /// A faixa da linha atual é desenhada aqui, e não numa subview: o
    /// `NSTextView` pinta o próprio fundo por cima das subviews, então uma
    /// view atrás simplesmente nunca apareceria. `drawBackground(in:)` roda
    /// antes de o texto ser desenhado, que é exatamente o lugar certo.
    public override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard let rect = currentLineRect, rect.intersects(dirtyRect) else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).setFill()
        rect.fill()
    }

    /// Chamado pelo delegate antes de cada edição — cobre digitação, colagem
    /// e delete, que passam todos por `shouldChangeTextIn`.
    func registerEdit() {
        let now = Date()
        let isContinuation = lastEditDate.map { now.timeIntervalSince($0) <= undoCoalescingInterval } ?? false

        if !isContinuation {
            closeUndoGroup()
            undoManager?.beginUndoGrouping()
            isUndoGroupOpen = true
        }
        lastEditDate = now

        closeGroupTimer?.invalidate()
        closeGroupTimer = Timer.scheduledTimer(withTimeInterval: undoCoalescingInterval, repeats: false) { [weak self] _ in
            // O timer roda no run loop principal.
            MainActor.assumeIsolated { self?.closeUndoGroup() }
        }
    }

    func closeUndoGroup() {
        closeGroupTimer?.invalidate()
        closeGroupTimer = nil
        lastEditDate = nil
        guard isUndoGroupOpen else { return }
        undoManager?.endUndoGrouping()
        isUndoGroupOpen = false
    }

    /// Range de fundo da linha atual, em coordenadas do text view.
    var currentLineRect: NSRect? {
        guard let layoutManager, textStorage?.length ?? 0 > 0 else { return nil }
        let glyph = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: selectedRange().location, length: 0),
            actualCharacterRange: nil
        ).location
        var rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        rect.origin.x = 0
        rect.size.width = bounds.width
        return rect
    }

    /// Descarta o realce anterior, voltando aos atributos base.
    func resetAttributes() {
        textStorage?.setAttributes(
            SyntaxTheme.baseAttributes(baseFont: font ?? EditorFont.mono()),
            range: NSRange(location: 0, length: textStorage?.length ?? 0)
        )
    }
}

/// Scroll view + gutter + text view.
public final class CodeEditorContainerView: NSView {
    let textView: EditorTextView
    let scrollView = NSScrollView()

    private let gutter: LineNumberGutterView

    init(textView: EditorTextView) {
        self.textView = textView
        self.gutter = LineNumberGutterView(textView: textView)
        super.init(frame: .zero)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        // Respiro entre o gutter e o texto: sem isso a primeira coluna fica
        // colada na linha do número, como o Xcode evita.
        textView.textContainerInset = NSSize(width: Metrics.unit * 2, height: Metrics.unit)
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        gutter.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        addSubview(gutter)

        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: Metrics.gutterWidth),

            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é suportado")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func contentViewDidScroll() {
        gutter.needsDisplay = true
    }

    func textViewDidChangeLayout() {
        updateCurrentLine()
        gutter.needsDisplay = true
    }

    /// A faixa é desenhada por `EditorTextView.drawBackground(in:)`; aqui
    /// só é preciso forçar o redesenho quando a seleção muda de linha.
    func updateCurrentLine() {
        textView.needsDisplay = true
    }

    func setMarkers(_ markers: [Int: LineNumberGutterView.Marker]) {
        gutter.markers = markers
        gutter.needsDisplay = true
    }

    // MARK: - Comandos de edição

    public func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    /// `performFindPanelAction:` é um action do AppKit e não aparece no
    /// header do SDK, então o selector é escrito à mão.
    private static let findPanelAction = NSSelectorFromString("performFindPanelAction:")

    /// Abre a find bar nativa do AppKit. Existe há décadas e já tem o
    /// comportamento certo — reimplementar seria perder de graça.
    public func showFindBar() {
        focusEditor()
        NSApp.sendAction(Self.findPanelAction, to: textView, from: nil)
    }

    /// `line` é 1-based; fora do intervalo vai para a primeira/última linha.
    public func goToLine(_ line: Int) {
        let starts = TextBuffer.lineStartOffsets(of: textView.string)
        guard !starts.isEmpty else { return }
        let index = min(max(line - 1, 0), starts.count - 1)
        let location = starts[index]
        textView.setSelectedRange(NSRange(location: location, length: 0))
        focusEditor()
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        textViewDidChangeLayout()
    }

    /// Comenta ou descomenta as linhas selecionadas, com indentação
    /// preservada. Se todas as linhas com conteúdo já estiverem comentadas,
    /// descomenta todas.
    public func toggleComment() {
        guard let storage = textView.textStorage else { return }
        let nsString = storage.string as NSString
        let selection = textView.selectedRange()
        let anchor = min(selection.location, max(nsString.length - 1, 0))
        let lineRange = nsString.lineRange(
            for: selection.length == 0 ? NSRange(location: anchor, length: 0) : selection
        )

        let lineLocations = lineStarts(in: nsString, within: lineRange)
        let affectedLineCount = lineLocations.count

        var allCommented = true
        var hasContent = false
        for location in lineLocations {
            let body = body(of: location, in: nsString)
            if body.isEmpty { continue }
            hasContent = true
            if !body.hasPrefix("//") { allCommented = false }
        }
        let shouldComment = !(hasContent && allCommented)

        storage.beginEditing()
        // De baixo para cima: cada edição muda o tamanho do documento e
        // invalidaria os offsets ainda não visitados.
        for location in lineLocations.reversed() {
            let body = body(of: location, in: nsString)
            let indent = indent(of: location, in: nsString)
            if shouldComment {
                if !body.isEmpty {
                    storage.insert(NSAttributedString(string: "// "), at: location + indent)
                }
            } else if body.hasPrefix("//") {
                var remove = 2
                if body.dropFirst(2).hasPrefix(" ") { remove = 3 }
                storage.deleteCharacters(in: NSRange(location: location + indent, length: remove))
            }
        }
        storage.endEditing()

        // Editar o storage programaticamente colapsa a seleção. Sem
        // resselecionar, um segundo ⌘/ desfaria só a última linha em vez
        // de todo o bloco.
        restoreSelection(startingAt: lineRange.location, lineCount: affectedLineCount)
    }

    /// Recoloca a seleção cobrindo `lineCount` linhas a partir de `location`.
    private func restoreSelection(startingAt location: Int, lineCount: Int) {
        guard lineCount > 0, let storage = textView.textStorage else { return }
        let updated = storage.string as NSString
        let tail = NSRange(location: location, length: max(updated.length - location, 0))
        let starts = lineStarts(in: updated, within: tail)
        guard let first = starts.first, starts.count >= lineCount else { return }
        let lastLine = starts[lineCount - 1]
        let end = updated.lineRange(for: NSRange(location: lastLine, length: 0))
        textView.setSelectedRange(NSRange(location: first, length: NSMaxRange(end) - first))
    }

    /// Início de cada linha contida em `range`.
    ///
    /// Precisa enumerar por linha e não mapear cada offset: dois offsets da
    /// mesma linha produzem o mesmo início, e comentar a mesma linha duas
    /// vezes duplica o `//`.
    private func lineStarts(in text: NSString, within range: NSRange) -> [Int] {
        var locations: [Int] = []
        text.enumerateSubstrings(
            in: range,
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            locations.append(lineRange.location)
        }
        return locations
    }

    /// Conteúdo da linha sem indentação nem terminador.
    private func body(of location: Int, in text: NSString) -> String {
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        var line = text.substring(with: lineRange)
        while let last = line.last, last == "\n" || last == "\r" || last == "\t" || last == " " {
            line.removeLast()
        }
        return String(line.drop(while: { $0 == " " || $0 == "\t" }))
    }

    private func indent(of location: Int, in text: NSString) -> Int {
        let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
        let line = text.substring(with: lineRange)
        return line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }
}

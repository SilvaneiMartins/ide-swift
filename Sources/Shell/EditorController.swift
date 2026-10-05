import DesignSystem
import EditorCore
import Observation

/// Ponte entre os menus do SwiftUI e o `NSTextView` em foco.
///
/// O container registra a si mesmo quando ganha foco; os comandos do menu
/// (`⌃L`, `⌘/`, `⌘F`) passam por aqui. Sem isso, um `CommandMenu` do
/// SwiftUI não tem como alcançar o AppKit.
@MainActor
@Observable
public final class EditorController {
    fileprivate weak var container: CodeEditorContainerView?

    public init() {}

    func attach(_ container: CodeEditorContainerView) {
        self.container = container
    }

    func detach(_ container: CodeEditorContainerView) {
        if self.container === container { self.container = nil }
    }

    public var hasEditor: Bool { container != nil }

    public func goToLine(_ line: Int) { container?.goToLine(line) }
    public func toggleComment() { container?.toggleComment() }
    public func showFindBar() { container?.showFindBar() }
    public func focusEditor() { container?.focusEditor() }
}

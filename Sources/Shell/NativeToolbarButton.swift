import AppKit
import SwiftUI

/// Botão nativo de toolbar. Um `Button` do SwiftUI não produz o mesmo
/// componente do AppKit na barra unificada — é preciso `NSButton` com
/// `bezelStyle` para ter o comportamento nativo (a11y, menu, foco).
///
/// `.plain` é o visual das referências de design: só o ícone, sem moldura.
/// `.filled` é o botão "clássico" de toolbar, que pesa demais num app que
/// quer ser minimalista.
struct NativeToolbarButton: NSViewRepresentable {
    enum Style {
        case plain
        case filled
    }

    let symbol: String
    let help: String
    let isEnabled: Bool
    let style: Style
    let action: () -> Void

    init(
        symbol: String,
        help: String,
        isEnabled: Bool = true,
        style: Style = .plain,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.help = help
        self.isEnabled = isEnabled
        self.style = style
        self.action = action
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.controlSize = .small
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.toolTip = help
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        configure(button)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    private func configure(_ button: NSButton) {
        switch style {
        case .plain:
            button.bezelStyle = .texturedRounded
            button.isBordered = false
        case .filled:
            button.bezelStyle = .texturedRounded
            button.isBordered = true
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        button.isEnabled = isEnabled
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}
